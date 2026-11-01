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

MATRIX_SERVER_NAME هویت دائمی Matrix است. پس از اجرای scripts/init.sh هرگز آن را تغییر ندهید. ابتدا یک‌بار init را اجرا کنید تا مسیر TLS ساخته شود، گواهی‌ها را قرار دهید و سپس استک را بالا بیاورید. نخستین `make up` آنلاین imageهای پین‌شده و Element Web با checksum تأییدشده را خودکار آماده می‌کند؛ اجرای آفلاین بعدی از `offline-bundle` تأییدشده استفاده می‌کند.

~~~sh
bash scripts/init.sh
chmod 600 secrets/tls/fullchain.pem secrets/tls/privkey.pem
make up
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
make restart
make update

make MODE=local up
make MODE=local status
make MODE=local logs
make MODE=local down
make MODE=local restart
make MODE=local update
~~~

`make up` فقط در صورت نیاز init می‌کند، داده را reset نمی‌کند، Element لازم را
در حالت آنلاین با checksum تأییدشده آماده یا `offline-bundle` را تأیید و استفاده
می‌کند، از imageهای دانلودشده استفاده می‌کند، منتظر health check می‌ماند و dashboard چاپ می‌کند.
URLهای Element، Matrix API و در حالت محلی Admin از تنظیمات تولیدشده خوانده
می‌شوند. یک URL فقط پس از بررسی موفق HTTP در دسترس علامت می‌خورد. `make down`
فقط کانتینرها را stop می‌کند و volume یا دادهٔ کاربر را حذف نمی‌کند. `make help`
فهرست فرمان‌ها را نشان می‌دهد. `make restart` تنظیمات مدیریت‌شده را دوباره تولید
و فقط Synapse/Nginx (و Admin محلی یا coturn فعال) را recreate می‌کند، نه
PostgreSQL. `make update` هرگز Git را تغییر نمی‌دهد: ابتدا خودتان `git pull
--ff-only` را اجرا کنید؛ سپس فقط image پین‌شدهٔ گم‌شده را pull، asset تأییدشدهٔ
گم‌شده را آماده و همین restart امن را انجام می‌دهد. هر دو فرمان با image/asset
cache‌شده آفلاین کار می‌کنند.

## تنظیمات

.env.example متغیرهای پشتیبانی‌شده را نشان می‌دهد: MATRIX_SERVER_NAME، PUBLIC_BASE_URL، متغیرهای PostgreSQL، MAX_UPLOAD_SIZE، MEDIA_UPLOAD_LIMIT_24H، MEDIA_UPLOAD_LIMIT_7D، LOCAL_HOST، LOCAL_ELEMENT_PORT و LOCAL_ADMIN_PORT.

مقادیر پیش‌فرض upload به‌ترتیب 20M، 100M و 500M هستند. Ketesa فقط در مسیر /admin/ در دسترس است. Compose متغیرها را در فایل‌های mount‌شده جای‌گذاری نمی‌کند؛ scripts/init.sh و scripts/render-config.py فایل‌های تولیدشده را در data/ می‌سازند و دامنه، URL، پورت، نام دیتابیس و اندازه‌ها را اعتبارسنجی می‌کنند.

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

Element در http://LOCAL_HOST:LOCAL_ELEMENT_PORT و Ketesa در http://LOCAL_HOST:LOCAL_ADMIN_PORT/admin/ است.

Ketesa فقط به loopback محدود می‌ماند؛ در تولید دسترسی عمومی Admin API یا پنل مدیریتی وجود ندارد.

~~~sh
COMPOSE_FILE=compose.local.yaml COMPOSE_PROJECT_NAME=matrix_local scripts/users.sh create alice
COMPOSE_FILE=compose.local.yaml COMPOSE_PROJECT_NAME=matrix_local scripts/media.sh usage
~~~

## مدیریت کاربر و مجوزهای اتاق

Admin UI محدود به loopback از Admin API native Synapse استفاده می‌کند. server
admin می‌تواند کاربر، device/session و عضویت اتاق را بررسی یا مدیریت کند و این
دسترسی در تولید منتشر نمی‌شود. helper محلی زیر actionهای native را که ممکن است
در نسخهٔ پین‌شدهٔ Admin UI دیده نشوند پوشش می‌دهد:

~~~sh
scripts/users.sh devices alice
scripts/users.sh lock alice
scripts/users.sh suspend alice
scripts/users.sh revoke-device alice DEVICE_ID
scripts/users.sh revoke-all alice
scripts/users.sh password alice       # reset گذرواژه و logout deviceها
scripts/users.sh deactivate alice     # پیام/رسانه را erase نمی‌کند
~~~

lock، suspend، لغو device و deactivate نیازمند تایپ تأیید نمایش‌داده‌شده‌اند.
`unlock` و `unsuspend` محدودیت خود را برمی‌گردانند؛ deactivate مخرب‌تر است زیرا
Synapse device، token، password material و عضویت اتاق را حذف می‌کند، اما پیام
ارسال‌شده، رسانهٔ آپلودشده یا backup را خودکار حذف نمی‌کند. لغو device token آن
را نامعتبر می‌کند و ممکن است تاریخچهٔ رمزگذاری‌شده روی همان دستگاه قابل‌بازیابی
نباشد.

مدیر اتاق با server admin متفاوت است. در Element بخش **Room Settings** و
**People** و **Roles & Permissions** برای invite، حذف، ban و تعیین Matrix power
level استفاده می‌شود. power levelهای خود Matrix، ارسال، invite، kick، ban،
تنظیمات/state اتاق و `m.room.retention` را سمت‌سرور کنترل می‌کنند و عضو عادی
هیچ اختیار سراسری ندارد. این پروژه block سراسری invite قبلی را برداشته تا invite
مدیر اتاق ممکن شود. Matrix ACL سراسریِ ریزتر از power level برای هر اتاق ندارد؛
برای سیاست دقیق‌تر event مربوط به power level همان اتاق را تنظیم کنید.

**Import room keys** در Element، import تاریخچهٔ chat نیست: export رمزدارِ کلیدهای
E2EE Megolm را فقط در مرورگر/دستگاه همان کاربر وارد می‌کند. Element Web 1.12.33
تنظیم پشتیبانی‌شده‌ای برای غیرفعال‌کردن فقط این قابلیت محلی ندارد و Synapse نیز
نمی‌تواند آن را enforce کند. هیچ switch گمراه‌کنندهٔ server-side یا fork رابط
رمزگذاری اضافه نشده است؛ این کار پیام import، join اتاق، upload رسانه یا script
backup/export پروژه نیست.

## نگه‌داری و حذف اتاق

موتور native نگه‌داری پیام Synapse فعال است. پیش‌فرض هر اتاق **خاموش** است؛ تا
زمانی که یک state event مجاز تنظیم نشود، نگه‌داری نامحدود است. Synapse زمان مؤثر
را بین ۱ تا ۹۰ روز محدود می‌کند و purge روزانهٔ خود را اجرا می‌کند. مدیر اتاق
(معمولاً power level 100؛ power level خود اتاق تعیین‌کننده است) می‌تواند state key
خالی و `m.room.retention` را با یکی از این محتواها تنظیم کند:

| انتخاب | `max_lifetime` (میلی‌ثانیه) |
| --- | ---: |
| خاموش | `{}` |
| ۱ روز | `86400000` |
| ۷ روز | `604800000` |
| ۳۰ روز | `2592000000` |
| ۹۰ روز | `7776000000` |

Element Web 1.12.33 برای این قابلیت experimental، انتخاب‌گر پشتیبانی‌شده در
Room Settings ندارد. بدون fork کلاینت، مدیر مجاز اتاق در composer فرمان
`/devtools` را باز می‌کند، **Send custom state event** را می‌زند، نوع را
`m.room.retention`، state key را خالی و JSON جدول را وارد می‌کند. عضو عادی در
power level معمول نمی‌تواند این state event را بفرستد و Synapse هر زمان درخواستی
را به ۱ تا ۹۰ روز محدود می‌کند. Synapse به‌صورت native فقط همین گزینه‌های جدول
را اجباری نمی‌کند.

رویدادهای منقضی ابتدا از timeline پنهان و سپس در اجرای بعدی purge روزانه از
دیتابیس Synapse پاک می‌شوند؛ پیام‌های قدیمی اتاق نیز با policy جدید پردازش
می‌شوند. state eventها، آخرین رویداد اتاق، cache کلاینت، نسخهٔ E2EE موجود در
دستگاه، export، رسانه و backup پاک نمی‌شوند. پس از به‌روزرسانی این پروژه، برای
افزودن block مدیریت‌شده به سرور قبلاً init‌شده، `bash scripts/init.sh` را اجرا و
Synapse را restart کنید.

برای حذف دائمی سمت‌سرور، از Synapse Admin محلی استفاده کنید: در **Rooms** شناسه
و جزئیات را بررسی کنید، **Delete room** را بزنید، فقط پس از بررسی هدف گزینهٔ
**purge** را فعال و تأیید صریح UI را کامل کنید. این کار Delete Room Admin API
احراز هویت‌شدهٔ Synapse را صدا می‌زند و فقط server admin مجاز است. پیش از کامل
دانستن عملیات status حذف را بررسی کنید. این کار `scripts/media.sh`، backup یا
نسخه‌های E2EE/کلاینت را خودکار حذف نمی‌کند و ممکن است برگشت‌ناپذیر باشد.

## امنیت حساب و دستگاه

ورود local-password در Synapse و Element Web 1.12.33 جریان کامل ثبت‌نام، بازیابی
و غیرفعال‌سازی TOTP یا passkey برای کاربر ندارند. هیچ 2FA ناقصی فعال نشده است؛
کلاینت mobile می‌تواند چنین لایه‌ای را با password login دور بزند. راه حداقلیِ
ممکن، مهاجرت طراحی‌شده به OIDC self-hosted (یا Matrix Authentication Service)
است که MFA لازم را فراهم کند؛ این کار سرویس احراز هویت، مهاجرت داده، endpoint
HTTPS و آزمون سازگاری اضافه می‌کند و خارج از استک سبک فعلی است.

Element Web PIN یا app-lock بیومتریکِ قابل‌تنظیم از سمت سرور ندارد. از قفل
مرورگر/سیستم‌عامل، رمزگذاری کامل دیسک، device verification و recovery key
Element استفاده کنید. Element mobile ممکن است بسته به پلتفرم و نسخه قفل بومی
داشته باشد؛ آن را روی خود دستگاه تنظیم کنید. این حفاظت محلی دستگاه است، نه 2FA
سمت‌سرور، و PIN هرگز به این سرور ارسال نمی‌شود.

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

