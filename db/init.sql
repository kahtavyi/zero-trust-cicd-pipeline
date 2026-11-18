-- Initial PostgreSQL schema and seed data for Ajax Systems model telemetry service.
CREATE TABLE IF NOT EXISTS public.devices (
    id SERIAL PRIMARY KEY,
    hub_id VARCHAR(64) UNIQUE NOT NULL,
    device_name VARCHAR(128) NOT NULL,
    device_type VARCHAR(64) NOT NULL,
    firmware_version VARCHAR(32) NOT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'online',
    battery_level INTEGER NOT NULL DEFAULT 100
);

INSERT INTO public.devices (hub_id, device_name, device_type, firmware_version, status, battery_level)
VALUES
    ('HUB-2P-001', 'Ajax Hub 2 Plus Central', 'Hub 2 Plus', 'OS Malevich 2.21.1', 'online', 100),
    ('MP-002', 'Ajax MotionProtect Corridor', 'MotionProtect', '5.55.2.0', 'online', 94),
    ('DP-003', 'Ajax DoorProtect Plus Entry', 'DoorProtect Plus', '5.58.1.0', 'online', 88),
    ('FP-004', 'Ajax FireProtect 2 ServerRoom', 'FireProtect 2', '6.10.4.0', 'online', 98)
ON CONFLICT (hub_id) DO NOTHING;
