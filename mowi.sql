-- 1. Tabla EMPRESA
CREATE TABLE Empresa (
    id_empresa NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR2(100) NOT NULL,
    ruc VARCHAR2(20) UNIQUE NOT NULL,
    direccion VARCHAR2(200),
    contacto VARCHAR2(100),
    email VARCHAR2(100),
    telefono VARCHAR2(20)
);

-- 2. Tabla USUARIO
CREATE TABLE Usuario (
    id_usuario NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR2(100) NOT NULL,
    email VARCHAR2(100) UNIQUE NOT NULL,
    telefono VARCHAR2(20),
    contrasena VARCHAR2(100) NOT NULL,
    rol VARCHAR2(20) CHECK (rol IN ('empleado', 'administrador')),
    id_empresa NUMBER NOT NULL,
    CONSTRAINT fk_usuario_empresa FOREIGN KEY (id_empresa) REFERENCES Empresa(id_empresa)
);

-- 3. Tabla SOLICITUD DE VIAJE
CREATE TABLE Solicitud_Viaje (
    id_solicitud NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha_solicitud DATE DEFAULT SYSDATE,
    origen VARCHAR2(200) NOT NULL,
    destino VARCHAR2(200) NOT NULL,
    hora_programada TIMESTAMP NOT NULL,
    estado VARCHAR2(20) CHECK (estado IN ('pendiente', 'asignado', 'completado', 'cancelado')),
    id_usuario NUMBER NOT NULL,
    CONSTRAINT fk_solicitud_usuario FOREIGN KEY (id_usuario) REFERENCES Usuario(id_usuario)
);

-- 4. Tabla CONDUCTOR
CREATE TABLE Conductor (
    id_conductor NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR2(100) NOT NULL,
    licencia VARCHAR2(50) UNIQUE NOT NULL,
    telefono VARCHAR2(20),
    estado VARCHAR2(20) CHECK (estado IN ('Activo', 'Inactivo', 'En viaje')),
    calificacion NUMBER(3,2) -- Permite valores como 4.95
);

-- 5. Tabla VEH�CULO
CREATE TABLE Vehiculo (
    id_vehiculo NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    marca VARCHAR2(50),
    modelo VARCHAR2(50),
    placa VARCHAR2(20) UNIQUE NOT NULL,
    capacidad NUMBER(2),
    tipo VARCHAR2(50), -- Ej: El�ctrico, H�brido, Gasolina
    estado VARCHAR2(20),
    id_conductor NUMBER,
    CONSTRAINT fk_vehiculo_conductor FOREIGN KEY (id_conductor) REFERENCES Conductor(id_conductor)
);

-- 6. Tabla VIAJE (Ejecuci�n real)
CREATE TABLE Viaje (
    id_viaje_real NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha_inicio TIMESTAMP,
    fecha_fin TIMESTAMP,
    distancia NUMBER(8,2), -- En kil�metros
    costo NUMBER(10,2), -- Costo del viaje
    estado VARCHAR2(20) CHECK (estado IN ('Solicitado', 'En curso', 'Finalizado')),
    id_solicitud NUMBER UNIQUE NOT NULL, -- Relaci�n 1:1 con la solicitud
    id_conductor NUMBER NOT NULL,
    id_vehiculo NUMBER NOT NULL,
    CONSTRAINT fk_viaje_solicitud FOREIGN KEY (id_solicitud) REFERENCES Solicitud_Viaje(id_solicitud),
    CONSTRAINT fk_viaje_conductor FOREIGN KEY (id_conductor) REFERENCES Conductor(id_conductor),
    CONSTRAINT fk_viaje_vehiculo FOREIGN KEY (id_vehiculo) REFERENCES Vehiculo(id_vehiculo)
);

-- 7. Tabla FACTURACI�N
CREATE TABLE Facturacion (
    id_factura NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha DATE DEFAULT SYSDATE,
    monto NUMBER(10,2) NOT NULL,
    estado_pago VARCHAR2(20) CHECK (estado_pago IN ('Pendiente', 'Pagado')),
    id_empresa NUMBER NOT NULL,
    CONSTRAINT fk_facturacion_empresa FOREIGN KEY (id_empresa) REFERENCES Empresa(id_empresa)
);

/* =============================================================================
   SP 1 CORREGIDO: Generación de Facturación
============================================================================= */
CREATE OR REPLACE PROCEDURE sp_generar_factura_empresa (
    p_id_empresa IN NUMBER,
    p_mes_anio   IN VARCHAR2
) IS
    v_monto_total NUMBER := 0;
    v_factura_existe NUMBER;
    
    CURSOR c_viajes IS
        SELECT v.costo
        FROM Viaje v
        JOIN Solicitud_Viaje s ON v.id_solicitud = s.id_solicitud
        JOIN Usuario u ON s.id_usuario = u.id_usuario
        WHERE u.id_empresa = p_id_empresa
          AND v.estado = 'Finalizado'
          AND TO_CHAR(s.fecha_solicitud, 'MM/YYYY') = p_mes_anio;
BEGIN
    -- [NUEVO] Validar que no hayamos facturado este mes ya
    SELECT COUNT(*) INTO v_factura_existe FROM Facturacion 
    WHERE id_empresa = p_id_empresa AND TO_CHAR(fecha, 'MM/YYYY') = p_mes_anio;
    
    IF v_factura_existe > 0 THEN
        RAISE_APPLICATION_ERROR(-20003, 'Ya existe una factura para este mes/año y empresa.');
    END IF;

    FOR r_viaje IN c_viajes LOOP
        v_monto_total := v_monto_total + NVL(r_viaje.costo, 0); 
    END LOOP;

    IF v_monto_total > 0 THEN
        INSERT INTO Facturacion (fecha, monto, estado_pago, id_empresa)
        VALUES (TO_DATE(p_mes_anio, 'MM/YYYY'), v_monto_total, 'Pendiente', p_id_empresa);
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Factura generada exitosamente.');
    ELSE
         DBMS_OUTPUT.PUT_LINE('No hay viajes con costos para facturar en este periodo.');
    END IF;
END sp_generar_factura_empresa;
/

/* =============================================================================
   SP 2 CORREGIDO: Asignar viaje (con bloqueo de conductor y validaciones)
============================================================================= */
CREATE OR REPLACE PROCEDURE sp_asignar_viaje (
    p_id_solicitud IN NUMBER
) IS
    v_id_conductor NUMBER;
    v_id_vehiculo  NUMBER;
    v_estado_sol NUMBER;
BEGIN
    -- [NUEVO] Validar que la solicitud sea apta para asignación y exista.
    SELECT COUNT(*) INTO v_estado_sol FROM Solicitud_Viaje 
    WHERE id_solicitud = p_id_solicitud AND estado = 'pendiente';
    
    IF v_estado_sol = 0 THEN
         RAISE_APPLICATION_ERROR(-20004, 'La solicitud no existe o no se encuentra en estado pendiente.');
    END IF;

    BEGIN
        SELECT c.id_conductor, v.id_vehiculo
        INTO v_id_conductor, v_id_vehiculo
        FROM Conductor c
        JOIN Vehiculo v ON c.id_conductor = v.id_conductor
        WHERE c.estado = 'Activo' AND ROWNUM = 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20001, 'No hay conductores activos/disponibles.');
    END;

    INSERT INTO Viaje (estado, id_solicitud, id_conductor, id_vehiculo)
    VALUES ('Solicitado', p_id_solicitud, v_id_conductor, v_id_vehiculo);

    UPDATE Solicitud_Viaje SET estado = 'asignado' WHERE id_solicitud = p_id_solicitud;
    -- [NUEVO] Marcamos al conductor como ocupado para que no le asignen doble simultáneamente
    UPDATE Conductor SET estado = 'En viaje' WHERE id_conductor = v_id_conductor;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Viaje y conductor asignados correctamente.');
END sp_asignar_viaje;
/

/* =============================================================================
   SP 3 CORREGIDO: Emisiones (Ligera mejora con DBMS_OUTPUT)
============================================================================= */
CREATE OR REPLACE PROCEDURE sp_calcular_emisiones_viaje (
    p_id_viaje IN NUMBER,
    p_co2      OUT NUMBER
) IS
    v_distancia NUMBER;
    v_tipo      VARCHAR2(50);
    v_factor    NUMBER;
BEGIN
    SELECT v.distancia, veh.tipo INTO v_distancia, v_tipo
    FROM Viaje v JOIN Vehiculo veh ON v.id_vehiculo = veh.id_vehiculo
    WHERE v.id_viaje_real = p_id_viaje;

    IF UPPER(v_tipo) IN ('ELECTRICO', 'ELÉCTRICO') THEN v_factor := 0.0;
    ELSIF UPPER(v_tipo) IN ('HIBRIDO', 'HÍBRIDO') THEN v_factor := 0.089;
    ELSE v_factor := 0.200;
    END IF;

    p_co2 := NVL(v_distancia, 0) * v_factor;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        p_co2 := 0;
        DBMS_OUTPUT.PUT_LINE('ATENCIÓN: Viaje no encontrado.');
END sp_calcular_emisiones_viaje;
/

/* =============================================================================
   SP 4 CORREGIDO: Cancelación (con devolución del conductor)
============================================================================= */
CREATE OR REPLACE PROCEDURE sp_cancelar_solicitud (
    p_id_solicitud IN NUMBER
) IS
    v_estado_solicitud VARCHAR2(20);
    v_estado_viaje     VARCHAR2(20);
    v_id_conductor     NUMBER;
BEGIN
    -- [NUEVO] Encapsulando en bloque propio para evitar crasheo general.
    BEGIN
        SELECT estado INTO v_estado_solicitud FROM Solicitud_Viaje WHERE id_solicitud = p_id_solicitud;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20010, 'La solicitud indicada a cancelar no existe.');
    END;

    IF v_estado_solicitud = 'pendiente' THEN
        UPDATE Solicitud_Viaje SET estado = 'cancelado' WHERE id_solicitud = p_id_solicitud;
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Solicitud sin conductor ha sido cancelada.');
        
    ELSIF v_estado_solicitud = 'asignado' THEN
        BEGIN
            SELECT estado, id_conductor INTO v_estado_viaje, v_id_conductor FROM Viaje WHERE id_solicitud = p_id_solicitud;

            IF v_estado_viaje = 'En curso' THEN
                RAISE_APPLICATION_ERROR(-20002, 'El viaje ya está en curso, no se puede cancelar.');
            ELSE
                UPDATE Solicitud_Viaje SET estado = 'cancelado' WHERE id_solicitud = p_id_solicitud;
                -- [NUEVO] Liberamos al conductor que quedó atascado para que pueda recibir otro trabajo
                UPDATE Conductor SET estado = 'Activo' WHERE id_conductor = v_id_conductor; 
                DELETE FROM Viaje WHERE id_solicitud = p_id_solicitud;
                COMMIT;
                DBMS_OUTPUT.PUT_LINE('Viaje cancelado exitosamente y Conductor liberado.');
            END IF;
        END;
    END IF;
END sp_cancelar_solicitud;
/
--------------------------------------------------------------
---INSERCION DE DATOS DE PRUEBA 
-- Habilitar los mensajes en pantalla para las validaciones
SET SERVEROUTPUT ON; 

-- 1. Empresas
INSERT INTO Empresa (nombre, ruc, direccion, contacto, email, telefono) VALUES ('Tech Corp', '12345678901', 'Av. Central 123', 'Juan Perez', 'contacto@techcorp.com', '555-1234');
INSERT INTO Empresa (nombre, ruc, direccion, contacto, email, telefono) VALUES ('Innovate LLC', '09876543210', 'Calle False 123', 'Maria Garcia', 'maria@innovate.com', '555-5678');

-- 2. Usuarios
INSERT INTO Usuario (nombre, email, telefono, contrasena, rol, id_empresa) VALUES ('Ana Lopez', 'ana.lopez@techcorp.com', '555-8881', 'pass123', 'empleado', 1);
INSERT INTO Usuario (nombre, email, telefono, contrasena, rol, id_empresa) VALUES ('Carlos Ruiz', 'carlos.ruiz@innovate.com', '555-8882', 'pass123', 'administrador', 2);

-- 3. Conductores
INSERT INTO Conductor (nombre, licencia, telefono, estado, calificacion) VALUES ('Miguel Sánchez', 'LIC-001', '555-3331', 'Activo', 4.8);
INSERT INTO Conductor (nombre, licencia, telefono, estado, calificacion) VALUES ('Luisa Fernández', 'LIC-002', '555-3332', 'Activo', 4.9);
INSERT INTO Conductor (nombre, licencia, telefono, estado, calificacion) VALUES ('José Martínez', 'LIC-003', '555-3333', 'Inactivo', 4.5);

-- 4. Vehículos (Asociados a sus conductores)
INSERT INTO Vehiculo (marca, modelo, placa, capacidad, tipo, estado, id_conductor) VALUES ('Toyota', 'Prius', 'ABC-123', 4, 'Híbrido', 'Operativo', 1);
INSERT INTO Vehiculo (marca, modelo, placa, capacidad, tipo, estado, id_conductor) VALUES ('Tesla', 'Model 3', 'XYZ-987', 4, 'Eléctrico', 'Operativo', 2);

-- 5. Solicitudes de Viaje (3 Casos de Uso Distintos)
-- Solicitud #1: Vamos a asignarla y finalizarla artificialmente para tener algo para "Facturar"
INSERT INTO Solicitud_Viaje (fecha_solicitud, origen, destino, hora_programada, estado, id_usuario) 
VALUES (TO_DATE('15/02/2026', 'DD/MM/YYYY'), 'Sucursal Sur', 'Oficina Central', SYSDATE, 'completado', 1);

    -- Forzamos la creación del viaje concluido correspondiente a la Solicitud #1 (Para probar SP Facturador)
    INSERT INTO Viaje (fecha_inicio, fecha_fin, distancia, costo, estado, id_solicitud, id_conductor, id_vehiculo)
    VALUES (SYSDATE-1, SYSDATE, 25.5, 65.50, 'Finalizado', 1, 1, 1);

-- Solicitud #2: La utilizaremos para demostrar la Asignación Automática limpia.
INSERT INTO Solicitud_Viaje (origen, destino, hora_programada, estado, id_usuario) 
VALUES ('Oficina Norte', 'Aeropuerto', SYSDATE + 1, 'pendiente', 1);

-- Solicitud #3: La intentaremos cancelar más adelante luego de asignar chofer.
INSERT INTO Solicitud_Viaje (origen, destino, hora_programada, estado, id_usuario) 
VALUES ('Terminal Centro', 'Almacén', SYSDATE + 5, 'pendiente', 2);

COMMIT;
------------------------------
--ejecucion procedimientos almacenados
---------------------------
---1.escenario
BEGIN
    -- Generar factura para Empresa 1 ('Tech Corp') de la fecha que declaramos artificial ('02/2026')
    sp_generar_factura_empresa(1, '02/2026');
END;
/
-- Seleccionar para ver la factura generada creada
SELECT * FROM Facturacion; 

----2.escenario
BEGIN
    -- Asignaremos la solicitud #2 (Pendiente de Ana Lopez)
    sp_asignar_viaje(2);
END;
/
-- Verás que se generó un insert en Viajes y que Luisa o Miguel pasaron de "Activo" a "En viaje"
SELECT id_solicitud, estado FROM Solicitud_Viaje WHERE id_solicitud = 2;
SELECT nombre, estado FROM Conductor;
SELECT * FROM Viaje WHERE id_solicitud = 2;
-----3.escenario
DECLARE
    v_emision_calculada NUMBER;
BEGIN
    -- Calcularemos emisiones del viaje #1 insertado arriba (Cuyo carro 1 es Híbrido, y manejó 25.5 km). 
    -- Factor 0.089 * 25.5 = 2.2695
    sp_calcular_emisiones_viaje(1, v_emision_calculada);
    DBMS_OUTPUT.PUT_LINE('Emisión de CO2 Calculada: ' || v_emision_calculada || ' Kgs');
END;
/

----4. escenario
BEGIN
    -- 1. Primero, asignamos la Solicitud #3 a ver que sucede
    sp_asignar_viaje(3);
    
    -- 2.un error del usuario, canclacion del viaje.
    sp_cancelar_solicitud(3);
END;
/
-- Verificar que ya NO existe el registro en la tabla Viaje 
    SELECT * FROM Viaje WHERE id_solicitud = 3;

-- Verificar que el estado de la Solicitud ahora es 'Cancelado'
SELECT estado FROM Solicitud_Viaje WHERE id_solicitud = 3;

-- El conductor fue devuelto a 'Activo' en el SP y no quedó estancado
SELECT nombre, estado FROM Conductor;
