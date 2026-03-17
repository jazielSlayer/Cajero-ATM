

import { connect } from "../database.js";

const BASE_URL = "https://bo.dolarapi.com/v1/dolares";


const CACHE_TTL_MS = 10 * 60 * 1000;
let lastFetch = 0;
let memCache = {}; 

async function fetchDolarApi() {
    const now = Date.now();
    if (now - lastFetch < CACHE_TTL_MS && Object.keys(memCache).length > 0) {
        return; // todavía vigente
    }

    const [oficial, binance] = await Promise.all([
        fetch(`${BASE_URL}/oficial`).then((r) => r.json()),
        fetch(`${BASE_URL}/binance`).then((r) => r.json()),
    ]);

    const tasas = [
        
        { origen: "USD", destino: "BOB", tasa: oficial.venta,        tipo: "oficial" },
        { origen: "BOB", destino: "USD", tasa: 1 / oficial.venta,    tipo: "oficial" },
        
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


const USD_RATES = {
    BOB: null, 
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


export async function convertir(monto, origen, destino, tipo = "oficial") {
    const tasa = await getTasa(origen, destino, tipo);
    return { resultado: monto * tasa, tasa, tipo };
}


export async function getTasaBOB(moneda, tipo = "oficial") {
    if (moneda === "BOB") return 1;
    return getTasa(moneda, "BOB", tipo);
}