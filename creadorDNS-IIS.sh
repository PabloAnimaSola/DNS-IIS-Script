#!/bin/bash
## Requisito de sudo ##
if [[ $EUID -ne 0 ]]; then
  echo "Tienes que correr el script con root. Usa sudo. (sudo ./creadorDNS-IIS.sh)" >&2
  exit 1
fi
## Declaración de Variables ##
equipo=$(hostname)
IP=""
nombrePagina=""
dominio=""
nombreCompleto=""
confPagina=""
confSecPagina=""
csrPagina=""
crtPagina=""
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
nombreCompleto=$nombrePagina"."$dominio
confPagina=$dominio".conf"
confSecPagina=$dominio"-ssl.conf"
csrPagina=$nombrePagina".csr"
keyPagina=$nombrePagina".key"
crtPagina=$nombrePagina".crt"
#############
## Solicitud de la IP sin máscara ##
read -p "Ahora introduce la direccion IP que tendrá la página web SIN LA MÁSCARA: " IP
echo "Tu netplan tiene que tener ya configurado el adaptador con la dirección y el DNS establecido"
#############
## Creación de la estructura del directorio ##
mkdir -p /var/www/"$dominio"
sudo cp /var/www/"$dominio"/index.html /var/www/"$dominio"
echo "Estructura de directorio creada"
#############
## Crear los hosts virtuales para cada dominio ##
cd /etc/apache2/sites-available/
cp 000-default.conf "$confPagina"
cp default-ssl.conf "$confSecPagina"
a2ensite "$confPagina" && systemctl restart apache2
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
openssl genrsa -des3 -out "$keyPagina"
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
sed -i $"94c\\\SSLOptions +FakeBasicAuth +ExportCertData +StrictRequire" "$confSecPagina"
#############
