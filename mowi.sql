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

-- 5. Tabla VEHÍCULO
CREATE TABLE Vehiculo (
    id_vehiculo NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    marca VARCHAR2(50),
    modelo VARCHAR2(50),
    placa VARCHAR2(20) UNIQUE NOT NULL,
    capacidad NUMBER(2),
    tipo VARCHAR2(50), -- Ej: Eléctrico, Híbrido, Gasolina
    estado VARCHAR2(20),
    id_conductor NUMBER,
    CONSTRAINT fk_vehiculo_conductor FOREIGN KEY (id_conductor) REFERENCES Conductor(id_conductor)
);

-- 6. Tabla VIAJE (Ejecución real)
CREATE TABLE Viaje (
    id_viaje_real NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha_inicio TIMESTAMP,
    fecha_fin TIMESTAMP,
    distancia NUMBER(8,2), -- En kilómetros
    costo NUMBER(10,2), -- Costo del viaje
    estado VARCHAR2(20) CHECK (estado IN ('Solicitado', 'En curso', 'Finalizado')),
    id_solicitud NUMBER UNIQUE NOT NULL, -- Relación 1:1 con la solicitud
    id_conductor NUMBER NOT NULL,
    id_vehiculo NUMBER NOT NULL,
    CONSTRAINT fk_viaje_solicitud FOREIGN KEY (id_solicitud) REFERENCES Solicitud_Viaje(id_solicitud),
    CONSTRAINT fk_viaje_conductor FOREIGN KEY (id_conductor) REFERENCES Conductor(id_conductor),
    CONSTRAINT fk_viaje_vehiculo FOREIGN KEY (id_vehiculo) REFERENCES Vehiculo(id_vehiculo)
);

-- 7. Tabla FACTURACIÓN
CREATE TABLE Facturacion (
    id_factura NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha DATE DEFAULT SYSDATE,
    monto NUMBER(10,2) NOT NULL,
    estado_pago VARCHAR2(20) CHECK (estado_pago IN ('Pendiente', 'Pagado')),
    id_empresa NUMBER NOT NULL,
    CONSTRAINT fk_facturacion_empresa FOREIGN KEY (id_empresa) REFERENCES Empresa(id_empresa)
);
/* =============================================================================
   ESCENARIO 1: Generación De Facturación Consolidada Mensual
============================================================================= */
CREATE OR REPLACE PROCEDURE sp_generar_factura_empresa (
    p_id_empresa IN NUMBER,
    p_mes_anio   IN VARCHAR2 -- Formato esperado: 'MM/YYYY'
) IS
    v_monto_total NUMBER := 0;
    
    CURSOR c_viajes IS
        SELECT v.costo
        FROM Viaje v
        JOIN Solicitud_Viaje s ON v.id_solicitud = s.id_solicitud
        JOIN Usuario u ON s.id_usuario = u.id_usuario
        WHERE u.id_empresa = p_id_empresa
          AND v.estado = 'Finalizado' -- Ajustado al CHECK de tu tabla
          AND TO_CHAR(s.fecha_solicitud, 'MM/YYYY') = p_mes_anio;
BEGIN
    FOR r_viaje IN c_viajes LOOP
        -- Sumamos asegurando que no haya valores nulos
        v_monto_total := v_monto_total + NVL(r_viaje.costo, 0); 
    END LOOP;

    IF v_monto_total > 0 THEN
        -- Omitimos id_factura porque es IDENTITY y se genera solo
        INSERT INTO Facturacion (fecha, monto, estado_pago, id_empresa)
        VALUES (TO_DATE(p_mes_anio, 'MM/YYYY'), v_monto_total, 'Pendiente', p_id_empresa);
        
        COMMIT;
    END IF;
END sp_generar_factura_empresa;
/

/* =============================================================================
   ESCENARIO 2: Asignación Automática De Viaje
============================================================================= */
CREATE OR REPLACE PROCEDURE sp_asignar_viaje (
    p_id_solicitud IN NUMBER
) IS
    v_id_conductor NUMBER;
    v_id_vehiculo  NUMBER;
BEGIN
    BEGIN
        SELECT c.id_conductor, v.id_vehiculo
        INTO v_id_conductor, v_id_vehiculo
        FROM Conductor c
        JOIN Vehiculo v ON c.id_conductor = v.id_conductor
        WHERE c.estado = 'Activo' -- Ajustado al CHECK de Conductor
          AND ROWNUM = 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20001, 'No hay conductores activos/disponibles.');
    END;

    -- Omitimos id_viaje_real porque es IDENTITY. Estado en formato Título por tu CHECK.
    INSERT INTO Viaje (estado, id_solicitud, id_conductor, id_vehiculo)
    VALUES ('Solicitado', p_id_solicitud, v_id_conductor, v_id_vehiculo);

    -- Actualizamos en minúscula por el CHECK de Solicitud_Viaje
    UPDATE Solicitud_Viaje
    SET estado = 'asignado' 
    WHERE id_solicitud = p_id_solicitud;

    COMMIT;
END sp_asignar_viaje;
/

/* =============================================================================
   ESCENARIO 3: Cálculo De Huella De Carbono
============================================================================= */
CREATE OR REPLACE PROCEDURE sp_calcular_emisiones_viaje (
    p_id_viaje IN NUMBER,
    p_co2      OUT NUMBER
) IS
    v_distancia NUMBER;
    v_tipo      VARCHAR2(50);
    v_factor    NUMBER;
BEGIN
    SELECT v.distancia, veh.tipo
    INTO v_distancia, v_tipo
    FROM Viaje v
    JOIN Vehiculo veh ON v.id_vehiculo = veh.id_vehiculo
    WHERE v.id_viaje_real = p_id_viaje;

    -- Contemplamos tildes por si acaso
    IF UPPER(v_tipo) IN ('ELECTRICO', 'ELÉCTRICO') THEN
        v_factor := 0.0;
    ELSIF UPPER(v_tipo) IN ('HIBRIDO', 'HÍBRIDO') THEN
        v_factor := 0.089;
    ELSE
        v_factor := 0.200;
    END IF;

    p_co2 := NVL(v_distancia, 0) * v_factor;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        p_co2 := 0;
END sp_calcular_emisiones_viaje;
/

/* =============================================================================
   ESCENARIO 4: Cancelación Segura De Solicitud
============================================================================= */
CREATE OR REPLACE PROCEDURE sp_cancelar_solicitud (
    p_id_solicitud IN NUMBER
) IS
    v_estado_solicitud VARCHAR2(50);
    v_estado_viaje     VARCHAR2(50);
BEGIN
    SELECT estado 
    INTO v_estado_solicitud
    FROM Solicitud_Viaje
    WHERE id_solicitud = p_id_solicitud;

    IF v_estado_solicitud = 'pendiente' THEN
        UPDATE Solicitud_Viaje
        SET estado = 'cancelado'
        WHERE id_solicitud = p_id_solicitud;
        COMMIT;
        
    ELSIF v_estado_solicitud = 'asignado' THEN
        BEGIN
            SELECT estado 
            INTO v_estado_viaje
            FROM Viaje
            WHERE id_solicitud = p_id_solicitud;

            IF v_estado_viaje = 'En curso' THEN
                RAISE_APPLICATION_ERROR(-20002, 'El viaje ya está en curso, no se puede cancelar.');
            ELSE
                UPDATE Solicitud_Viaje SET estado = 'cancelado' WHERE id_solicitud = p_id_solicitud;
                
                -- ATENCIÓN: Como tu tabla 'Viaje' no tiene 'Cancelado' en su CHECK constraint, 
                -- la mejor práctica para mantener la integridad es eliminar el viaje no iniciado.
                DELETE FROM Viaje WHERE id_solicitud = p_id_solicitud;
                
                COMMIT;
            END IF;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                UPDATE Solicitud_Viaje SET estado = 'cancelado' WHERE id_solicitud = p_id_solicitud;
                COMMIT;
        END;
    END IF;
END sp_cancelar_solicitud;
/