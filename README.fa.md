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

## تنظیمات

.env.example متغیرهای پشتیبانی‌شده را نشان می‌دهد: MATRIX_SERVER_NAME، PUBLIC_BASE_URL، متغیرهای PostgreSQL، MAX_UPLOAD_SIZE، MEDIA_UPLOAD_LIMIT_24H، MEDIA_UPLOAD_LIMIT_7D، LOCAL_HOST، LOCAL_ELEMENT_PORT، LOCAL_ADMIN_PORT و ADMIN_PATH.

مقادیر پیش‌فرض upload به‌ترتیب 20M، 100M و 500M هستند. ADMIN_PATH به‌طور پیش‌فرض / است و مسیرهایی مانند /panel، /admin یا /management معتبرند. Compose متغیرها را در فایل‌های mount‌شده جای‌گذاری نمی‌کند؛ scripts/init.sh و scripts/render-config.py فایل‌های تولیدشده را در data/ می‌سازند و دامنه، URL، پورت، مسیر، نام دیتابیس و اندازه‌ها را اعتبارسنجی می‌کنند.

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

