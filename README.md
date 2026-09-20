# sonda

caja de herramientas de radio, red y sensores para el iPhone, con la estética de [girasol](https://github.com/kisnner26/girasol). inspirada en lo que hace un flipper zero, limitada a lo que un iPhone puede hacer de verdad y sin cuenta de pago de desarrollador. mira, mide y explica: no clona, no emula y no interfiere.

## qué hace

**bluetooth**
- escáner de dispositivos BLE con señal, distancia aproximada, fabricante y tipo (iBeacon, Eddystone, AirPods, Fast Pair…), con el volcado de los datos de fabricante.
- **detector de rastreadores**: reconoce accesorios de la red Encontrar de Apple (AirTag y compatibles), Tile y Samsung SmartTag.
- modo búsqueda: vibra más rápido cuanto más fuerte llega la señal.
- explorador GATT: conecta, lista servicios y características con sus nombres estándar, lee, escucha notificaciones y escribe (con confirmación).

**red**
- direcciones y subred de tus interfaces, **bonjour** (impresoras, AirPlay, SSH, HomeKit…), barrido de equipos de la subred, escáner de puertos, **ping ICMP** con pérdida y jitter, y DNS directo e inverso.

**sensores**
- campo magnético con **detector de metales** (sonido y háptico), presión y altura relativa, brújula con coordenadas, y nivel de burbuja con pico de fuerza g.

**audio**
- analizador de espectro con **detector de ultrasonido**, generador de tonos y barridos, teclado y decodificador **DTMF**, sonómetro y **morse** por sonido y linterna.

**cámara**
- lector de QR y códigos de barras que entiende Wi-Fi, contactos, geo, correo, SMS y claves OTP, y **avisa de enlaces sospechosos** (http, IP en vez de dominio, punycode, usuario falso antes de la @).
- **detector de infrarrojo**: comprueba si un mando a distancia emite.

**herramientas**
- visor hex de archivos, hashes (MD5, SHA, CRC-32) con comparación, conversiones (texto, hex, base64, binario, URL), generador de contraseñas con entropía y azar (dados, moneda).

## lo que un iPhone no puede (y sonda no finge)

| función del flipper | en el iPhone |
|---|---|
| sub-GHz, RFID de 125 kHz, iButton, GPIO, BadUSB | no hay hardware |
| infrarrojo emisor | no hay emisor (la cámara sí ve el de un mando) |
| leer etiquetas NFC | CoreNFC **exige cuenta de pago**; con la gratuita no se puede instalar |
| emular o clonar NFC | iOS lo bloquea |
| Wi-Fi en modo monitor, nombre de la red | iOS lo reserva (el nombre exige cuenta de pago) |

## instalar en tu iPhone

necesitas un mac con xcode y una cuenta de apple (la gratuita sirve; el perfil dura 7 días).

```bash
brew install xcodegen
TEAM_ID=TU_TEAM_ID ./scripts/install-iphone.sh
```

la primera vez, confía en tu perfil en *Ajustes > General > VPN y gestión de dispositivos*. no hace falta simulador.

## pruebas

la lógica vive en el paquete `SondaCore` (análisis de anuncios BLE, subredes, puertos, ICMP, FFT, DTMF, morse, hashes, análisis de QR, detector de destellos) y se prueba con `swift test`.

## límites, con honestidad

- la distancia por Bluetooth sale de la potencia de la señal y fluctúa mucho: sirve para "cerca o lejos".
- el barrido de equipos cuenta un equipo como presente si acepta o rechaza una conexión TCP; uno que descarta todo no aparece.
- el sonómetro es relativo (dBFS), sin calibrar.
- el detector de infrarrojo no decodifica mandos: la señal va a 38 kHz y la cámara no llega.
- escanea solo redes y equipos tuyos o con permiso.

licencia MIT.
