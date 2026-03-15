

import { connect } from "../database.js";

const BASE_URL = "https://bo.dolarapi.com/v1/dolares";

// TTL: 10 minutos (en ms). No golpeamos la API en cada petición.
const CACHE_TTL_MS = 10 * 60 * 1000;
let lastFetch = 0;
let memCache = {}; // { "BOB-USD-oficial": tasa, ... }

// ─────────────────────────────────────────────────────────────────────────────
//  fetchDolarApi  –  llama a la API externa y actualiza memCache + BD
// ─────────────────────────────────────────────────────────────────────────────
async function fetchDolarApi() {
    const now = Date.now();
    if (now - lastFetch < CACHE_TTL_MS && Object.keys(memCache).length > 0) {
        return; // todavía vigente
    }

    const [oficial, binance] = await Promise.all([
        fetch(`${BASE_URL}/oficial`).then((r) => r.json()),
        fetch(`${BASE_URL}/binance`).then((r) => r.json()),
    ]);

    // La API devuelve { compra, venta, ... } en BOB por 1 USD
    // Usamos "venta" (cuántos BOB cuesta 1 USD) para convertir USD→BOB
    // y 1/venta para BOB→USD
    const tasas = [
        // oficial
        { origen: "USD", destino: "BOB", tasa: oficial.venta,        tipo: "oficial" },
        { origen: "BOB", destino: "USD", tasa: 1 / oficial.venta,    tipo: "oficial" },
        // binance
        { origen: "USD", destino: "BOB", tasa: binance.venta,        tipo: "binance" },
        { origen: "BOB", destino: "USD", tasa: 1 / binance.venta,    tipo: "binance" },
    ];

    const connection = await connect();

    for (const { origen, destino, tasa, tipo } of tasas) {
        const key = `${origen}-${destino}-${tipo}`;
        memCache[key] = tasa;

        await connection.query(
            `INSERT INTO tasa_cambio_cache
                 (Moneda_origen, Moneda_destino, Tasa, Tipo_tasa)
             VALUES (?, ?, ?, ?)
             ON DUPLICATE KEY UPDATE
                 Tasa                = VALUES(Tasa),
                 Fecha_actualizacion = current_timestamp()`,
            [origen, destino, tasa, tipo]
        );
    }

    lastFetch = now;
    console.log(
        `[TasaCambio] Tasas actualizadas — oficial venta: ${oficial.venta} BOB/USD | binance venta: ${binance.venta} BOB/USD`
    );
}

// ─────────────────────────────────────────────────────────────────────────────
//  getTasa  –  devuelve la tasa de conversión entre dos monedas
//
//  Parámetros:
//    origen   – código ISO (BOB, USD, EUR…)
//    destino  – código ISO
//    tipo     – 'oficial' | 'binance'
//
//  Retorna: número  (cuántas unidades de `destino` equivalen a 1 `origen`)
//
//  Lógica de conversión:
//    BOB → USD  →  tasa directa desde API
//    USD → BOB  →  tasa directa desde API
//    X   → BOB  →  primero X→USD (tasas globales hardcodeadas), luego USD→BOB
//    BOB → X    →  primero BOB→USD, luego USD→X
// ─────────────────────────────────────────────────────────────────────────────

// Tasas aproximadas respecto al USD (puedes reemplazarlas con otra API)
// 1 USD = N unidades de la moneda
const USD_RATES = {
    BOB: null, // se sobreescribe con la API
    USD: 1,
    EUR: 0.92,
    BRL: 5.05,
    ARS: 950,
    CLP: 950,
    PEN: 3.73,
    COP: 4100,
};

export async function getTasa(origen, destino, tipo = "oficial") {
    await fetchDolarApi();

    if (origen === destino) return 1;

    const key = `${origen}-${destino}-${tipo}`;
    if (memCache[key]) return memCache[key];

    // Conversión triangular a través de USD
    const origenUSD =
        origen === "USD" ? 1 : origen === "BOB"
            ? memCache[`BOB-USD-${tipo}`]
            : 1 / (USD_RATES[origen] ?? 1);

    const usdDestino =
        destino === "USD" ? 1 : destino === "BOB"
            ? memCache[`USD-BOB-${tipo}`]
            : USD_RATES[destino] ?? 1;

    return origenUSD * usdDestino;
}

// ─────────────────────────────────────────────────────────────────────────────
//  convertir  –  convierte un monto de origen a destino
// ─────────────────────────────────────────────────────────────────────────────
export async function convertir(monto, origen, destino, tipo = "oficial") {
    const tasa = await getTasa(origen, destino, tipo);
    return { resultado: monto * tasa, tasa, tipo };
}

// ─────────────────────────────────────────────────────────────────────────────
//  getTasaBOB  –  cuántos BOB vale 1 unidad de `moneda`
//                 (lo que necesitan los SPs)
// ─────────────────────────────────────────────────────────────────────────────
export async function getTasaBOB(moneda, tipo = "oficial") {
    if (moneda === "BOB") return 1;
    return getTasa(moneda, "BOB", tipo);
}