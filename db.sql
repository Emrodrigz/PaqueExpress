CREATE DATABASE IF NOT EXISTIS eval3;
use eval3;

CREATE TABLE agentes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    email VARCHAR(120) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL
);

CREATE TABLE paquetes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    paquete_uid VARCHAR(64) UNIQUE NOT NULL,
    direccion VARCHAR(255) NOT NULL,
    lat FLOAT NOT NULL,
    lon FLOAT NOT NULL
);

CREATE TABLE entregas (
    id INT AUTO_INCREMENT PRIMARY KEY,
    paquete_id INT NOT NULL,
    agente_id INT NOT NULL,
    foto_url VARCHAR(255) NOT NULL,
    gps_lat FLOAT NOT NULL,
    gps_lon FLOAT NOT NULL,
    fecha DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (paquete_id) REFERENCES paquetes(id),
    FOREIGN KEY (agente_id) REFERENCES agentes(id)
);

