# Mapa de Sevilla Este

Web social para el barrio de **Sevilla Este y Alcosa** (Sevilla). Los vecinos pueden descubrir y añadir lugares sobre un mapa propio, valorarlos, subir fotos, guardar favoritos y hablar en un foro con noticias, sala general y chats privados.

Se puede **mirar todo sin cuenta**. Para crear, valorar, comentar o escribir hay que iniciar sesión.

## Funciones

**Mapa**
- Mapa propio del barrio con contorno fijo y cinco niveles de detalle: según el zoom se muestran zonas y avenidas, barrios, calles principales y parques, y todas las calles. Mientras se hace zoom se ve una versión sin nombres para que la transición sea fluida.
- Buscador de lugares en la parte superior.
- Chinchetas por categoría (comer, eventos, compras, ocio, servicios, otros).
- Los lugares más destacados se ordenan por valoraciones, visitas y fotos, y el administrador puede marcar lugares como destacados a mano.

**Lugares**
- Cualquier persona registrada puede crear un lugar (solo dentro del contorno del barrio), y su creador puede editarlo o eliminarlo.
- Reseñas con estrellas y comentario (una por persona y lugar), botón "Estuve aquí hoy" y fotos.
- Quien sube una foto o una reseña puede borrarla. El creador del lugar puede **ocultar** reseñas y fotos (se ven tapadas y se pueden desocultar).
- Favoritos privados para cada usuario.

**Cuentas**
- Registro con nombre de usuario, email y contraseña.
- Inicio de sesión con **email o nombre de usuario**.

**Foro**
- Noticias (solo las publica el administrador), sala General y chats privados **por invitación**.
- Los lugares se pueden compartir en el foro como tarjeta con enlace al mapa.
- Filtro de enlaces: solo se admiten enlaces de una lista de sitios de confianza, y hay límite de mensajes por minuto.

**Administración**
- El rol de administrador se asigna desde la base de datos. Puede borrar o editar lugares, reseñas, fotos y mensajes, ver cualquier chat y destacar lugares.

## Tecnologías

- HTML, CSS y JavaScript sin compilar (no hace falta instalar nada para editarlo).
- [Leaflet](https://leafletjs.com/)
- [Supabase](https://supabase.com/) para la base de datos (PostgreSQL), cuentas, almacenamiento de fotos y permisos por filas (RLS).

## Estructura del proyecto

```
index.html     Página principal y lógica del mapa
style.css      Estilos de toda la web
foro.js        Foro: noticias, general, chats e invitaciones
config.js      URL y clave pública de Supabase, y contorno del barrio
setup.sql      Base de datos completa (tablas, permisos, funciones)
login.ts       Función de Supabase para entrar con nombre de usuario
img/           Imágenes del mapa (base, n1, n2, n3, n4)
```

## Puesta en marcha

### 1. Crear el proyecto en Supabase
1. Crea un proyecto en [supabase.com](https://supabase.com).
2. Abre `setup.sql`, cambia el nombre de usuario de la línea marcada con `AQUÍ ELIGES AL ADMIN` por el tuyo y pégalo entero en **SQL Editor > New query > Run**.
3. En **Project Settings > API** copia el *Project URL* y la clave *anon public*.

### 2. Configurar la web
Edita `config.js` y pega ahí tu URL y tu clave `anon`:

```js
const SUPABASE_URL = "https://TU-PROYECTO.supabase.co";   // sin barra final ni /rest/v1
const SUPABASE_KEY = "TU_CLAVE_ANON_PUBLIC";
```

### 3. Entrar con nombre de usuario (opcional)
En **Edge Functions > Deploy a new function > Via Editor**, crea una función llamada `login` y pega el contenido de `login.ts`. Sin ella, solo se puede entrar con el email.

### 4. Correo de confirmación
Supabase, sin servicio de correo propio, solo envía correos a los miembros de tu equipo y con un límite muy bajo. Para probar puedes desactivar *Confirm email* en **Authentication > Sign In / Providers > Email**. Para uso real, configura un servicio SMTP propio en **Authentication > Emails > SMTP Settings**.

### 5. Probarlo en local
Abre la carpeta en Visual Studio Code, instala la extensión **Live Server** y haz clic derecho sobre `index.html` > *Open with Live Server*. Añade `http://127.0.0.1:5500` en **Authentication > URL Configuration > Redirect URLs**.

> No funciona abriendo `index.html` con doble clic: hace falta servirlo desde una dirección web.

### 6. Publicarlo
Sirve cualquier alojamiento de páginas estáticas (GitHub Pages, Netlify...). Cuando tengas la dirección pública, añádela en **Authentication > URL Configuration** (*Site URL* y *Redirect URLs*).

## Niveles de zoom del mapa

En `index.html`, la lista `NIVELES` indica a partir de qué zoom se usa cada imagen. Puedes ajustar los valores de `z` para cambiar cuándo aparece cada nivel de detalle.

## Seguridad

- La clave `anon` de Supabase es **pública por diseño**: va dentro de la web. Lo que protege los datos son las políticas de seguridad por filas (RLS) que crea `setup.sql`.
- **Nunca** subas a este repositorio la clave `service_role` ni ninguna otra clave secreta.
- El filtro de enlaces y el límite de mensajes se aplican en la base de datos, no solo en la web. Aun así, no es un sistema perfecto: conviene moderar.

## Pendiente de hacer

- Recuperar contraseña ("olvidé mi contraseña").
- Mensajes del foro en tiempo real (ahora se actualizan cada pocos segundos).
- Sistema de denuncias de usuarios.
- Mover un lugar de posición al editarlo.

## Licencia

*Pendiente de elegir.* Mientras no se indique una licencia, el código queda con todos los derechos reservados.
