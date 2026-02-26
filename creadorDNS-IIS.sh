#!/bin/bash
## Declaración de colores ##
RESET='\033[0m' #Reinicia el color
ROJO='\033[1;31m'
AZUL='\033[1;36m'
VERDE='\033[0;32m'
###############
## Requisito de sudo ##
if [[ $EUID -ne 0 ]]; then
  echo -e "${ROJO}Tienes que correr el script con root, elevando permisos...${RESET}"
  sudo bash ~/DNS-IIS-Script/creadorDNS-IIS.sh
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
cat >> "$confZonasDNS" <<EOF

zone "$nombreCompleto" {
	type master;
	file "/etc/bind/zones/db.${nombrePagina}.conf";
};

zone "${IPInv}.in-addr.arpa" {
	type master;
	file "/etc/bind/zones/db.${dirIPInv}";
};

EOF

echo -e "${VERDE}¡Zonas creadas!${RESET}"
}

recargar(){
	systemctl restart "$1"
}

##############
## Introducción ##
clear
echo "Bienvenido al script de creación de páginas de IIS y vinculación de DNS"
echo "Antes de continuar, asegúrate de tener instalado apache2, bind9, y ufw (sudo apt install apache2 bind9 ufw)"
echo "Necesitas también tener la estructura básica de las carpetas de bind y apache (zonas y el nombre de la página respectivamente)."
echo -e "${AZUL}Eres la máquina" "$equipo${RESET}"
read -p "Introduce cualquier cosa para continuar..." Confirmar

#############
## Solicitud de los nombres de las zonas y direcciones IP ##
read -p "Introduce el nombre de la página web sin el dominio (Ej: realzaragoza): " nombrePagina
read -p "Ahora introduce el tipo de dominio (Ej: org, edu, com, es): " dominio

#############
## Creación de las variables de páginas del dominio ##
nombreCompleto="${nombrePagina}.${dominio}"
confPagina="${nombreCompleto}.conf"
confSecPagina="${nombreCompleto}-ssl.conf"
csrPagina="${nombrePagina}.csr"
keyPagina="${nombrePagina}.key"
crtPagina="${nombrePagina}.crt"

#############
## Solicitud de la IP sin máscara e IP inversa##
read -p "Ahora introduce la direccion IP que tendrá la página web SIN LA MÁSCARA: " IP
read -p "Escribe su dirección de zona inversa (Ej: 192.168.20.10/16 -> 168.192): " IPInv
dirIPInv=${IPInv}".in-addr.arpa"
echo "Tu netplan tiene que tener ya configurado el adaptador con la dirección y el DNS establecido"

#############
## Creación de la estructura del directorio ##
mkdir -p "/var/www/$nombrePagina"
cp /var/www/html/index.html "/var/www/$nombrePagina/index.html"
echo "Estructura de directorio creada"

#############
## Crear los hosts virtuales para cada dominio ##
cd /etc/apache2/sites-available/ || exit 1
cp 000-default.conf "$confPagina"
cp default-ssl.conf "$confSecPagina"
a2ensite "$confPagina" && recargar "apache2"
echo -e "${VERDE}Añadidos los archivos de configuración y apache reiniciado${RESET}"
#############
## Cambio de la página de configuración ##
sed -i $"10c\\\tDirectoryIndex index.html" "$confPagina"
sed -i $"11c\\\tServerAdmin webmaster@$nombreCompleto" "$confPagina"
sed -i $"12c\\\tDocumentRoot /var/www/$nombrePagina" "$confPagina"
sed -i $"13c\\\tServerName $equipo.$nombreCompleto" "$confPagina"
sed -i $"14c\\\tServerAlias www.$nombreCompleto" "$confPagina"
echo -e "${VERDE}Cambiados archivos de configuración de la página de HTTP${RESET}"
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
sed -i $"4c\\\tDocumentRoot /var/www/$nombrePagina" "$confSecPagina"
sed -i $"5c\\\tServerName $equipo.$nombreCompleto" "$confSecPagina"
sed -i $"6c\\\tServerAlias www.$nombreCompleto" "$confSecPagina"
sed -i $"31c\\\tSSLCertificateFile\\t/etc/ssl/certs/$crtPagina" "$confSecPagina"
sed -i $"32c\\\tSSLCertificateKeyFile\\t/etc/ssl/private/$keyPagina" "$confSecPagina"
sed -i $"94c\\\tSSLOptions +FakeBasicAuth +ExportCertData +StrictRequire" "$confSecPagina"
#############
echo -e "${VERDE}Configuración ya añadida, reiniciando apache.${RESET}"
recargar "apache2"
## Configuración de DNS ##
cd /etc/bind/
sed -i $"13c\\\tforwarders {" "$confFWDNS"
sed -i $"14c\\\t\t8.8.8.8;" "$confFWDNS"
sed -i $"15c\\\t\t1.1.1.1;" "$confFWDNS"
sed -i $"16c\\\t\t8.8.4.4;" "$confFWDNS"
sed -i $"17c\\\t};" "$confFWDNS"
sed -i '/^};/i\\tlisten-on { any; };\n\tallow-query { any; };\n' "$confFWDNS"
#############
## Editar named.config.local para añadir las zonas directa e inversa ##
echo -e "${VERDE}Forwarders del DNS Configurado, creando zonas del DNS.${RESET}"
if [ -d "$zonas" ]; then
	echo "El directorio de zones ya existe, editando named.conf.local."
	creacion_dns
else
	echo "La carpeta de zones NO existe, creando carpeta y editando named.conf.local."
	mkdir -p "$zonas"
	creacion_dns
fi

#############
## Copiar los archivos de las zonas y editarlas ##
echo -e "${AZUL}Copiando archivos de plantilla db. ...${RESET}"
cp db.local /etc/bind/zones/db.${nombrePagina}.conf && cp db.127 /etc/bind/zones/db.${dirIPInv}
#############
## Editar la zona directa y inversa ##
echo -e "${AZUL}Editando zona directa y inversa...${RESET}"
cd /etc/bind/zones
sed -i $"5c\\@\tIN\tSOA\t${nombreCompleto}.\troot.${nombreCompleto}.  (" "db.${nombrePagina}.conf"
sed -i $"6c\\\t\t\t    100\t \t; Serial" "db.${nombrePagina}.conf"
sed -i $"12c\\@\tIN\tNS\t${equipo}." "db.${nombrePagina}.conf"
sed -i $"13c\\@\tIN\tA\t${IP}" "db.${nombrePagina}.conf"
sed -i $"14c\\www\tIN\tCNAME\t${nombreCompleto}." "db.${nombrePagina}.conf"
echo -e "${VERDE}¡Zona directa configurada!${RESET}"
echo -e "${AZUL}Configurando zona inversa...${RESET}"
##
sed -i $"5c\\@\tIN\tSOA\t${nombreCompleto}.\troot.${nombreCompleto}.  (" "db.${dirIPInv}"
sed -i $"6c\\\t\t\t    100\t \t; Serial" "db.${dirIPInv}"
sed -i $"12c\\@\tIN\tNS\t${equipo}." "db.${dirIPInv}"
echo -e "${ROJO}Es necesario especificar la dirección INVERSA de host:${RESET}"
echo -e "${AZUL} Ejemplo: 192.168.80.90/16 ->${RESET} ${VERDE}90.80${RESET}"
read "dirInvHost"
sed -i $"13c\\${dirInvHost}\tIN\tPTR\t${equipo}.${nombreCompleto}." "db.${dirIPInv}"
recargar "bind9"
echo -e "${VERDE}¡Zona inversa configurada y bind9 recargado!${RESET}"
echo -e "${VERDE}¡Proceso finalizado!${RESET}"
