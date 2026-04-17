import nodemailer from "nodemailer";

// Configura con tu proveedor SMTP (ejemplo: Gmail con App Password)
export const transporter = nodemailer.createTransport({
    host: process.env.SMTP_HOST || "smtp.gmail.com",
    port: Number(process.env.SMTP_PORT) || 587,
    secure: false,
    auth: {
        user: process.env.SMTP_USER,   // tu-correo@gmail.com
        pass: process.env.SMTP_PASS,   // App Password de Gmail
    },
});

export async function enviarCodigoVerificacion(correo, codigo) {
    await transporter.sendMail({
        from: `"Cajero ATM" <${process.env.SMTP_USER}>`,
        to: correo,
        subject: "Código de verificación – Cajero ATM",
        html: `
            <h2>Verificación de correo</h2>
            <p>Usa el siguiente código para completar tu registro:</p>
            <h1 style="letter-spacing:8px; color:#1a73e8;">${codigo}</h1>
            <p>Válido por <strong>10 minutos</strong>. Si no solicitaste esto, ignora este mensaje.</p>
        `,
    });
}

export async function enviarDatosRegistro(correo, { nombre, numero_cuenta, numero_tarjeta, pin, fecha_vencimiento }) {
    await transporter.sendMail({
        from: `"Cajero ATM" <${process.env.SMTP_USER}>`,
        to: correo,
        subject: "¡Registro exitoso! – Tus datos de acceso",
        html: `
            <h2>¡Bienvenido/a, ${nombre}!</h2>
            <p>Tu cuenta ha sido creada exitosamente. Guarda estos datos en un lugar seguro:</p>
            <table style="border-collapse:collapse; font-size:15px;">
                <tr><td style="padding:6px 12px;"><strong>Número de cuenta</strong></td><td style="padding:6px 12px;">${numero_cuenta}</td></tr>
                <tr><td style="padding:6px 12px;"><strong>Número de tarjeta</strong></td><td style="padding:6px 12px;">${numero_tarjeta}</td></tr>
                <tr><td style="padding:6px 12px;"><strong>Fecha de vencimiento</strong></td><td style="padding:6px 12px;">${fecha_vencimiento}</td></tr>
                <tr><td style="padding:6px 12px;"><strong>PIN</strong></td><td style="padding:6px 12px; color:#d93025;">${pin}</td></tr>
            </table>
            <p style="margin-top:16px; color:#888;">Por seguridad, este correo no volverá a mostrarte tu PIN. Guárdalo ahora.</p>
        `,
    });
}