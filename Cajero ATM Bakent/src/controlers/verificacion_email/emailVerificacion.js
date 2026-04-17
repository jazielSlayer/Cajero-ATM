// Mapa en memoria: correo → { codigo, expira, verificado }
const verificaciones = new Map();

const TTL_MS = 10 * 60 * 1000; // 10 minutos

export function generarCodigo() {
    return Math.floor(100000 + Math.random() * 900000).toString(); // 6 dígitos
}

export function guardarCodigo(correo, codigo) {
    verificaciones.set(correo, {
        codigo,
        expira: Date.now() + TTL_MS,
        verificado: false,
    });
}

export function validarCodigo(correo, codigo) {
    const entry = verificaciones.get(correo);
    if (!entry) return { ok: false, motivo: "No hay un código activo para este correo." };
    if (Date.now() > entry.expira) {
        verificaciones.delete(correo);
        return { ok: false, motivo: "El código ha expirado. Solicita uno nuevo." };
    }
    if (entry.codigo !== codigo) return { ok: false, motivo: "Código incorrecto." };

    // Marcar como verificado
    verificaciones.set(correo, { ...entry, verificado: true });
    return { ok: true };
}

export function correoEstaVerificado(correo) {
    const entry = verificaciones.get(correo);
    return !!(entry && entry.verificado && Date.now() <= entry.expira);
}

export function limpiarVerificacion(correo) {
    verificaciones.delete(correo);
}