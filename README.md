# Notchling

Muestra a los lados del notch, o en una ventanita flotante, qué está haciendo cada sesión de Claude Code del Mac.

## Instalar

```sh
scripts/build.sh --install   # la copia a ~/Applications y la abre
```

Requiere macOS 14 o posterior y las Command Line Tools (`xcode-select --install`); no hace falta Xcode.
Para que arranque con el Mac: icono de la barra de menús → **Abrir al iniciar sesión**.

## Estados

| Estado | Significado | Animación |
| --- | --- | --- |
| Permiso | Espera que apruebes una acción | Candado que se agita y borde pulsante |
| Pregunta | Espera una respuesta | Bocadillo que bota y borde pulsante |
| Revisar plan | Hay un plan por aprobar | Portapapeles que late y borde pulsante |
| Te necesita | Espera por otro motivo | Aviso que bota y borde pulsante |
| Error | El turno terminó con un error de la API | Triángulo rojo |
| Menú abierto | Hay un diálogo abierto en la sesión | Icono fijo |
| Listo | Acaba de terminar (5 min o hasta que pulses) | Check que se dibuja |
| Trabajando | Está pensando o usando herramientas | Anillo giratorio y brillo en el texto |
| 2º plano | Sigue corriendo un comando en segundo plano | Anillo lento |
| En espera | No está haciendo nada | Se encoge a lo mínimo |
| Detectada | Hay sesión, pero no publica su estado | Icono fijo |

Con varias sesiones manda la más urgente, y cada una tiene su punto de color.

## Uso

- **Ratón encima:** despliega la lista (en el notch, pasa por el propio notch). Con más de seis sesiones, haz scroll.
- **Barra de menús:** al llevar el ratón a la barra fuera del notch, las alas se recogen y dejan ver los menús de la app.
  Vuelven al salir, salvo que haya un menú de otra app abierto. Se desactiva en **Apartarse de los menús de las apps**.
- **Clic en una fila:** trae al frente la app que aloja la sesión.
- **Arrastrar:** la mueve a cualquier punto de cualquier pantalla. Junto a un notch se acopla; desde el notch se despega.
- **Clic derecho** o icono de la barra de menús: posición, modo compacto y demás opciones.

Posición automática: en el notch si solo usas la pantalla del portátil; arriba en el centro de la externa si hay una.
Cada combinación de monitores recuerda la posición que elijas.

## Cómo funciona

No usa hooks, no modifica `~/.claude` y no usa la red. Cada 0,4 s lee:

1. `~/.claude/sessions/<pid>.json`, donde Claude Code publica el estado de cada sesión.
2. La tabla de procesos, para descartar sesiones muertas y encontrar las que usan otro `CLAUDE_CONFIG_DIR`.
3. Lo nuevo de cada transcript, para el título y la acción en curso.

## Limitaciones

- El registro de sesiones es un **formato interno** de Claude Code (comprobado en 2.1.325–2.1.330) y puede cambiar.
  Si cambia, hay que revisar `Sources/NotchCore/StateResolver.swift`.
- Sin ese estado (versiones antiguas), se deduce del transcript y **los permisos no se pueden detectar**.
  Este camino solo está probado con datos simulados.
- No ve sesiones de la nube, SSH, contenedores, máquinas virtuales (como Cowork) ni otros usuarios del Mac.
- El clic activa la app, no la pestaña concreta. Las sesiones `--bg` o dentro de tmux no tienen app que activar.
- Junto al notch tapa los menús que lleguen hasta ahí mientras el ratón no esté en la barra de menús.
- La firma es local: para distribuirla hace falta un Developer ID y notarizarla.

## Desarrollo

```sh
swift test
scripts/build.sh
build/Notchling.app/Contents/MacOS/Notchling --demo   # recorre los estados
build/Notchling.app/Contents/MacOS/Notchling --dump   # lo que ve el detector, en JSON
```

`Sources/NotchCore` contiene la detección y la geometría; `Sources/Notchling`, la interfaz (AppKit + Core Animation).
