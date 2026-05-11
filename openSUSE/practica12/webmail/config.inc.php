<?php

// Base de datos (leída desde variables de entorno inyectadas por Docker)
$config['db_dsnw'] = sprintf(
    'mysql://%s:%s@roundcube_db/%s',
    getenv('RC_DB_USER'),
    getenv('RC_DB_PASSWORD'),
    getenv('RC_DB_NAME')
);

// Clave de cifrado de sesión (24 caracteres, desde variable de entorno)
$config['des_key'] = getenv('RC_DES_KEY') ?: 'reprobados_clave_24chars!';

// Servidor IMAP
$config['default_host'] = 'tls://mailserver';
$config['default_port'] = 143;
$config['imap_conn_options'] = [
    'ssl' => ['verify_peer' => false, 'verify_peer_name' => false, 'allow_self_signed' => true],
];

// Servidor SMTP
$config['smtp_server'] = 'tls://mailserver';
$config['smtp_port'] = 587;
$config['smtp_user'] = '%u';
$config['smtp_pass'] = '%p';
$config['smtp_conn_options'] = [
    'ssl' => ['verify_peer' => false, 'verify_peer_name' => false, 'allow_self_signed' => true],
];
$config['smtp_user'] = '%u';
$config['smtp_pass'] = '%p';
$config['smtp_conn_options'] = [
    'ssl' => ['verify_peer' => false, 'verify_peer_name' => false],
];

// Identidad institucional
$config['product_name'] = 'Reprobados Mail';
$config['username_domain'] = 'reprobados.com';
$config['mail_domain'] = 'reprobados.com';

// Interfaz
$config['skin'] = 'elastic';
$config['language'] = 'es_ES';

// Seguridad de sesión
$config['session_lifetime'] = 30;
$config['ip_check'] = true;

// Proxy inverso: confiar en cabeceras X-Forwarded-* de nginx
$config['proxy_whitelist'] = ['172.0.0.0/8'];

// Almacenamiento temporal
$config['temp_dir'] = '/tmp/roundcube-temp';

// Plugins activos
$config['plugins'] = ['archive', 'zipdownload'];
