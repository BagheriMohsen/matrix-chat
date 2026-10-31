# استک خصوصی Matrix

[English](README.md) | [فارسی](#فارسی)

<a id="فارسی"></a>

این مخزن یک استک خصوصی Matrix با Synapse، PostgreSQL، Nginx و Element Web است. در تولید فقط سه کانتینر پایدار دارد: Nginx، Synapse و PostgreSQL. پنل Synapse Admin فقط در محیط محلی اجرا می‌شود.

فدراسیون، ثبت‌نام عمومی، مهمان، فهرست اتاق‌های عمومی، alias و دسترسی عمومی Admin API غیرفعال‌اند. E2EE پشتیبانی می‌شود، ولی کاربران باید کلید بازیابی و تأیید دستگاه خود را نگه دارند.

## نیازمندی‌ها و نصب

به Linux AMD64، Docker Engine، Docker Compose، Python 3، curl، tar، دامنه و گواهی HTTPS معتبر نیاز دارید. فایل‌های fullchain.pem و privkey.pem را با مجوز 600 در secrets/tls/ بگذارید؛ پروژه گواهی صادر یا تمدید نمی‌کند.

~~~sh
git clone https://github.com/BagheriMohsen/matrix-chat.git
cd matrix-chat
cp .env.example .env
~~~

در .env دامنه، URL HTTPS همان دامنه و گذرواژهٔ بلند دیتابیس را تنظیم کنید:

~~~dotenv
MATRIX_SERVER_NAME=matrix.example.com
PUBLIC_BASE_URL=https://matrix.example.com
POSTGRES_PASSWORD=use-a-long-random-password-here
~~~

MATRIX_SERVER_NAME هویت دائمی Matrix است. پس از اجرای scripts/init.sh هرگز آن را تغییر ندهید.

~~~sh
ELEMENT_SHA256=04e180516430381d5f5e528ea345a435784bba26f76a84f106a623febd3fcd67 scripts/offline-export.sh
bash scripts/init.sh
cp -a offline-bundle/static/element/. data/element/
chmod 600 secrets/tls/fullchain.pem secrets/tls/privkey.pem
docker compose up -d --pull never
scripts/users.sh admin admin
~~~

Element روی PUBLIC_BASE_URL است. Synapse Admin در تولید منتشر نمی‌شود و /_synapse/admin/ پاسخ 404 می‌دهد.

## فرمان‌های روزمره

Makefile به‌صورت امن حالت تولید را انتخاب می‌کند. حالت محلی باید صریح انتخاب
شود و از وضعیت ماشین حدس زده نمی‌شود:

~~~sh
make up
make status
make logs
make down

make MODE=local up
make MODE=local status
make MODE=local logs
make MODE=local down
~~~

`make up` فقط در صورت نیاز init می‌کند، داده را reset نمی‌کند، از imageهای
دانلودشده استفاده می‌کند، منتظر health check می‌ماند و dashboard چاپ می‌کند.
URLهای Element، Matrix API و در حالت محلی Admin از تنظیمات تولیدشده خوانده
می‌شوند. یک URL فقط پس از بررسی موفق HTTP در دسترس علامت می‌خورد. `make down`
فقط کانتینرها را stop می‌کند و volume یا دادهٔ کاربر را حذف نمی‌کند. `make help`
فهرست فرمان‌ها را نشان می‌دهد.

## تنظیمات

.env.example متغیرهای پشتیبانی‌شده را نشان می‌دهد: MATRIX_SERVER_NAME، PUBLIC_BASE_URL، متغیرهای PostgreSQL، MAX_UPLOAD_SIZE، MEDIA_UPLOAD_LIMIT_24H، MEDIA_UPLOAD_LIMIT_7D، LOCAL_HOST، LOCAL_ELEMENT_PORT، LOCAL_ADMIN_PORT و ADMIN_PATH.

مقادیر پیش‌فرض upload به‌ترتیب 20M، 100M و 500M هستند. ADMIN_PATH به‌طور پیش‌فرض / است و مسیرهایی مانند /panel، /admin یا /management معتبرند. Compose متغیرها را در فایل‌های mount‌شده جای‌گذاری نمی‌کند؛ scripts/init.sh و scripts/render-config.py فایل‌های تولیدشده را در data/ می‌سازند و دامنه، URL، پورت، مسیر، نام دیتابیس و اندازه‌ها را اعتبارسنجی می‌کنند.

متغیرهای TURN_ENABLED، TURN_HOST، TURN_EXTERNAL_IP، TURN_PORT، TURN_TLS_PORT،
TURN_MIN_PORT، TURN_MAX_PORT و TURN_SHARED_SECRET برای تماس اختیاری هستند.
پیش‌فرض TURN_ENABLED=0 است؛ TURN_HOST باید همان MATRIX_SERVER_NAME و
TURN_EXTERNAL_IP باید IPv4 عمومی سرور باشد.

در اولین init، PostgreSQL مقادیر POSTGRES_DB، POSTGRES_USER و
POSTGRES_PASSWORD را از `.env` می‌گیرد و همان مقادیر در تنظیمات دیتابیس Synapse
تولید می‌شوند. تغییر POSTGRES_PASSWORD پس از ایجاد دیتابیس، نقش PostgreSQL را
خودکار تغییر نمی‌دهد؛ چرخش گذرواژه یک عملیات جداگانه و برنامه‌ریزی‌شده است.

پس از تغییر تنظیمات Nginx، Element یا مسیر پنل:

~~~sh
python3 scripts/render-config.py
docker compose up -d --force-recreate nginx
~~~

برای تغییر محدودیت Synapse، بخش مربوط در data/synapse/homeserver.yaml و برای محیط محلی در homeserver.local.yaml را تغییر دهید و Synapse را restart کنید. این‌ها محدودیت آپلود هستند، نه سهمیهٔ دائمی فضا؛ حذف خودکار رسانه فعال نیست.

## آزمایش محلی و پنل Admin

ابتدا تولید را stop کنید، زیرا دو استک دادهٔ مشترک دارند:

~~~sh
bash scripts/local-init.sh
docker compose -p matrix_local -f compose.local.yaml up -d --pull never
python3 scripts/local-admin.py
~~~

Element در http://LOCAL_HOST:LOCAL_ELEMENT_PORT و Admin در http://LOCAL_HOST:LOCAL_ADMIN_PORT به‌اضافهٔ ADMIN_PATH است. برای ADMIN_PATH=/panel از http://localhost:8081/panel/ استفاده کنید.

پراکسی محلی مسیر بدون slash را به slash‌دار هدایت می‌کند و assetها، refresh، navigation و درخواست‌های API را پشتیبانی می‌کند. پنل به loopback محدود می‌ماند؛ در تولید کانتینر Admin یا دسترسی عمومی Admin API وجود ندارد.

~~~sh
COMPOSE_FILE=compose.local.yaml COMPOSE_PROJECT_NAME=matrix_local scripts/users.sh create alice
COMPOSE_FILE=compose.local.yaml COMPOSE_PROJECT_NAME=matrix_local scripts/media.sh usage
~~~

## رسانه، پشتیبان، بازیابی و حالت آفلاین

~~~sh
scripts/media.sh usage
scripts/media.sh list-user '@alice:matrix.example.com'
scripts/media.sh info 'mxc://matrix.example.com/MEDIA_ID'
scripts/media.sh delete 'mxc://matrix.example.com/MEDIA_ID' --execute
scripts/backup.sh
scripts/restore.sh backups/TIMESTAMP
~~~

حذف رسانه تأیید می‌خواهد و ممکن است پیوند پیام را خراب کند. archive پشتیبان را پیش از انتقال رمزگذاری کنید. بازیابی تنها پس از تأیید، دادهٔ فعلی را کنار می‌گذارد.

## پیام صوتی و تماس

Element Web 1.12.33 از پیام صوتی پشتیبانی می‌کند: کاربر از composer ضبط، بازبینی
و ارسال می‌کند و مانند رسانهٔ عادی آن را دانلود یا پخش می‌کند. اتاق‌های رمزگذاری‌شده
و محدودیت‌های فعلی upload حفظ می‌شوند. ضبط میکروفون به secure context نیاز دارد:
HTTPS در تولید یا استثنای localhost مرورگر در محیط محلی. HTTP روی LAN برای ضبط
میکروفون پشتیبانی‌شده نیست.

تماس self-hosted قابل‌اعتماد عمداً در این استک سه‌کانتینری فعال نشده است. تنظیمات
Element نقطه‌های ورود پیش‌فرض Jitsi و Element Call را غیرفعال می‌کند تا سرویس
عمومی Element ناخواسته استفاده نشود. تماس خصوصی یک‌به‌یک به coturn self-hosted و
TURN credential در Synapse نیاز دارد؛ تماس گروهی به MatrixRTC آزمایش‌شده نیاز دارد
(فعلاً Element Call با LiveKit یا SFU سازگار). این‌ها به پورت‌های relay عمومی
UDP/TCP، NAT/public IP، TLS، TURN secret، monitoring و CPU/RAM بیشتر نیاز دارند.
سرور 2 GB برای این پیام‌رسان و coturn کوچک مناسب است، اما برای LiveKit گروهی
قابل‌اعتماد روی همان میزبان واقع‌بینانه نیست. غیرفعال بودن federation مانع تماس
کاربران محلی نمی‌شود.

تماس گروهی خارج از scope است: coturn فقط تماس legacy یک‌به‌یک را فعال می‌کند و
MatrixRTC/LiveKit به استک جداگانه، ظرفیت و آزمون کامل نیاز دارد.

### تماس یک‌به‌یک اختیاری

TURN_HOST را دامنهٔ Matrix، TURN_EXTERNAL_IP را IPv4 عمومی، TURN_ENABLED را 1 و
TURN_SHARED_SECRET را راز قوی تنظیم کنید. راز را بدون چاپ یا commit بسازید:

~~~sh
openssl rand -base64 48 | tr -d '\n'
make up CALLS=1
~~~

در firewall سرور و provider، TURN_PORT (3478) را برای UDP/TCP، TURN_TLS_PORT
(5349) را برای TCP و کل بازهٔ UDP از TURN_MIN_PORT تا TURN_MAX_PORT باز کنید. پشت
NAT همین پورت‌ها را forward و TURN_EXTERNAL_IP را آدرس عمومی قرار دهید. TURNS از
گواهی موجود استفاده می‌کند، پس TURN_HOST باید MATRIX_SERVER_NAME باشد. TURN روی
UDP TLS نیست، هرچند رسانهٔ WebRTC از DTLS-SRTP استفاده می‌کند.

coturn از credential زمان‌دار Synapse استفاده می‌کند؛ CLI و anonymous access
غیرفعال، مقصدهای private/multicast مسدود و TCP relay غیرفعال است. محدودیت Compose
آن 128 MiB و 0.5 CPU است، اما پهنای‌باند با تماس‌های relay شده رشد می‌کند.
`make down` آن را نیز stop می‌کند.

برای آزمون، دو Element Web احراز هویت‌شده را در دو شبکهٔ متفاوت وارد کنید، تماس
صوتی و سپس ویدیویی برقرار و دوطرفه بودن را بررسی کنید. در WebRTC diagnostics
مرورگر candidate نوع relay را ببینید و روی شبکهٔ محدودکننده تکرار کنید. سالم بودن
کانتینر به‌تنهایی موفقیت تماس نیست.

scripts/offline-export.sh imageهای پین‌شده، Element بررسی‌شده و قالب‌ها را صادر می‌کند. در مقصد checksumها را بررسی، imageها را load، Element را در data/element/ کپی و سپس init و docker compose up -d --pull never را اجرا کنید. bundle شامل .env، دادهٔ دیتابیس، کلیدها، گواهی یا رسانه نیست.

هرگز .env، data/، secrets/، backup یا رسانه را commit نکنید. اعلان push موبایل ممکن است به زیرساخت Apple/Google وابسته باشد و در زمان قطع اینترنت بین‌المللی تضمین‌شده نیست.

## بررسی

~~~sh
docker compose config
docker compose exec synapse python3 -m synapse.config -c /data/homeserver.yaml
docker compose exec nginx nginx -t
docker compose ps
~~~

ورود Element، اتاق خصوصی رمزگذاری‌شده، آپلود/دانلود، رد فایل بزرگ‌تر از حد و 404 بودن مسیر عمومی Admin API را نیز بررسی کنید. E2EE و بازیابی را روی دستگاه واقعی آزمایش کنید.

