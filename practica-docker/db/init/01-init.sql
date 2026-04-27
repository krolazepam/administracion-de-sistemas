-- ============================================================
-- Script de inicialización de la base de datos
-- Se ejecuta automáticamente la PRIMERA vez que arranca el
-- contenedor con un volumen db_data vacío.
-- ============================================================

-- Tabla de usuarios (requerimiento del enunciado)
CREATE TABLE IF NOT EXISTS usuarios (
    id          SERIAL PRIMARY KEY,
    nombre      VARCHAR(100) NOT NULL,
    email       VARCHAR(150) UNIQUE NOT NULL,
    password    VARCHAR(255) NOT NULL,
    rol         VARCHAR(30)  DEFAULT 'user',
    activo      BOOLEAN      DEFAULT TRUE,
    creado_en   TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
);

-- Datos de ejemplo para poder verificar persistencia (Prueba 10.1)
INSERT INTO usuarios (nombre, email, password, rol) VALUES
    ('Admin',      'admin@infra.local',  'hash_placeholder_1', 'admin'),
    ('Juan Pérez', 'juan@infra.local',   'hash_placeholder_2', 'user'),
    ('Ana López',  'ana@infra.local',    'hash_placeholder_3', 'user');

-- Índice para búsquedas por email
CREATE INDEX IF NOT EXISTS idx_usuarios_email ON usuarios(email);

-- Mostrar resultado de la inicialización
DO $$
BEGIN
    RAISE NOTICE 'Base de datos inicializada. Usuarios creados: %',
        (SELECT COUNT(*) FROM usuarios);
END $$;
