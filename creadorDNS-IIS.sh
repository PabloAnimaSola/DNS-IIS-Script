#!/bin/bash
## Requisito de sudo ##
if [[ $EUID -ne 0 ]]; then
  echo "Tienes que correr el script con root. Usa sudo. (sudo ./creadorDNS-IIS.sh)" >&2
  exit 1
fi
## Declaración de Variables ##
equipo=$(hostname)
IP=""
IPInv=""
nombrePagina=""
dominio=""
nombreCompleto=""
confPagina=""
confSecPagina=""
csrPagina=""
crtPagina=""
confFWDNS="named.conf.options"
confZonasDNS="named.conf.local"
zonas="/etc/bind/zones"
##############
## Funciones ##
creacion_dns(){
	sed -i '$a\zone $nombreCompleto {' "$confZonasDNS"
	sed -i '$a\	type master;' "$confZonasDNS"
	sed -i '$a\	file "/etc/bind/zones/db.$nombrePagina";}' "$confZonasDNS"
	sed -i '$a\zone "$(IPInv)" {' "$confZonasDNS"
	sed -i '$a\	type master;' "$confZonasDNS"
	sed -i '$a\	file "/etc/bind/zones/db.$dirIPInv";' "$confZonasDNS"
	sed -i '$a\}' "$confZonasDNS"
}
recarga_apache(){
	systemctl restart apache2
}
##############
## Introducción ##
clear
echo "Bienvenido al script de creación de páginas de IIS y vinculación de DNS"
echo "Antes de continuar, asegúrate de tener instalado apache2, bind9, y ufw (sudo apt install apache2 bind9 ufw)"
echo "Necesitas también tener la estructura básica de las carpetas de bind y apache (zonas y el nombre de la página respectivamente)."
echo "Eres la máquina" "$equipo"
read -p "Introduce cualquier cosa para continuar..." Confirmar
#############
## Solicitud de los nombres de las zonas y direcciones IP ##
read -p "Introduce el nombre de la página web sin el dominio (Ej: realzaragoza): " nombrePagina
read -p "Ahora introduce el tipo de dominio (Ej: org, edu, com, es): " dominio
#############
## Creación de las variables de páginas del dominio ##
nombreCompleto=$nombrePagina."$dominio"
confPagina=$nombreCompleto".conf"
confSecPagina=$nombreCompleto"-ssl.conf"
csrPagina=$nombrePagina".csr"
keyPagina=$nombrePagina".key"
crtPagina=$nombrePagina".crt"
#############
## Solicitud de la IP sin máscara e IP inversa##
read -p "Ahora introduce la direccion IP que tendrá la página web SIN LA MÁSCARA: " IP
read -p "Escribe su dirección de zona inversa (Ej: 192.168.20.10/16 -> 10.20): " IPInv
dirIPInv=$IPInv".in-addr.arpa"
echo "Tu netplan tiene que tener ya configurado el adaptador con la dirección y el DNS establecido"
#############
## Creación de la estructura del directorio ##
mkdir -p /var/www/"$nombrePagina"
sudo cp /var/www/html/index.html /var/www/"$nombrePagina"/index.html
echo "Estructura de directorio creada"
#############
## Crear los hosts virtuales para cada dominio ##
cd /etc/apache2/sites-available/
cp 000-default.conf "$confPagina"
cp default-ssl.conf "$confSecPagina"
a2ensite "$confPagina" && recarga_apache
echo "Añadidos los archivos de configuración y apache reiniciado"
#############
## Cambio de la página de configuración ##
sed -i $"10c\\\tDirectoryIndex index.html" "$confPagina"
sed -i $"11c\\\tServerAdmin webmaster@$nombreCompleto" "$confPagina"
sed -i $"12c\\\tDocumentRoot /var/www/$dominio" "$confPagina"
echo "Cambiados archivos de configuración de la página de HTTP"
#############
## Habilitar los archivos de configuración ##
systemctl reload apache2
#############
## Configurando SSL ##
echo "Configurando SSL..."
a2ensite "$confSecPagina"
a2enmod ssl
echo "SSL Activado, escribe la contraseña de la key:"
openssl genrsa -des3 -out "$keyPagina"
openssl req -new -key "$keyPagina" -out "$csrPagina"
openssl x509 -req -days 365 -in "$csrPagina" -signkey "$keyPagina" -out "$crtPagina"
cp "$keyPagina" /etc/ssl/private/
cp "$crtPagina" /etc/ssl/certs/
#############
## Creación de la página ya configurada ##
sed -i $"2c\\\tServerAdmin webmaster@$nombreCompleto" "$confSecPagina"
sed -i $"3c\\\tDirectoryIndex index.html" "$confSecPagina"
sed -i $"4c\\\tDocumentRoot /var/www/$dominio" "$confSecPagina"
sed -i $"31c\\\tSSLCertificateFile\\t/etc/ssl/certs/$crtPagina" "$confSecPagina"
sed -i $"32c\\\tSSLCertificateKeyFile\\t/etc/ssl/private/$keyPagina" "$confSecPagina"
sed -i $"94c\\\tSSLOptions +FakeBasicAuth +ExportCertData +StrictRequire" "$confSecPagina"
#############
echo "Configuración ya añadida, reiniciando apache."
recarga_apache
## Configuración de DNS ##
cd /etc/bind/
sed -i $"13c\\\tforwarders {" "$confFWDNS"
sed -i $"14c\\\t\t8.8.8.8;" "$confFWDNS"
sed -i $"15c\\\t\t1.1.1.1;" "$confFWDNS"
sed -i $"16c\\\t\t8.8.4.4;" "$confFWDNS"
sed -i $"17c\\\t};" "$confFWDNS"
sed -i $"24c\\\tlisten-on { any; };" "$confFWDNS"
sed -i '$a\	allow-query { any; };' "$confFWDNS"
sed -i '$a\};' "$confFWDNS"
#############
## Creación de la carpeta zones y copia de archivos ##
echo "DNS Configurado, creando carpeta zones."
if [ -d "$zonas" ]; then
	echo "El directorio de zonas ya existe, creando dentro de la carpeta."
	creacion_dns
else
	echo "La carpeta de zonas NO existe, creando carpeta y editando."
	mkdir "$zonas"
	creacion_dns
fi
