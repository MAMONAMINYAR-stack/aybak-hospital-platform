# 01 — Audit Report | گزارش ممیزی (اجنت ۱)

- **Audited commit / کامیت ممیزی‌شده:** `9c1b9f8` — working tree clean, no files modified during audit
- **Date / تاریخ:** 2026-11-05
- **Method / روش:** بررسی فقط‌خواندنی کد + `npm install --no-package-lock` + `npm run build` + پروب سرور dev + تلاش برای `npm audit`
- **Stack / پشته:** React 18.3 + Vite 5.4.21 + Tailwind CSS 4 + react-router-dom 7 — فرانت‌اند فقط، بدون بک‌اند

## English summary

Frontend-only demo hospital app. Build passes, but: no lockfile (irreproducible installs, `npm audit`/`npm ci` impossible), fake client-side auth with hardcoded credentials shown in UI, zero tests, no CI, no README, no license, a 545-line monolithic `App.jsx`, unlabeled synthetic patient/prescription data, several no-op controls, no error boundary, minor a11y gaps, and a Vite dev-server config that blocks the Arena preview host (HTTP 403). Clinical/legal items (real auth, PHI handling, prescription logic, license choice) are flagged **needs-approval only** per Stage-0 decision "real product".

## یافته‌ها (هر مورد با شواهد)

شدت: 🔴 بحرانی | 🟠 زیاد | 🟡 متوسط | 🔵 کم

### F-01 🟠 نبود lockfile — نصب تکرارپذیر نیست
- **شواهد:** `ls package-lock.json` → `No such file or directory`؛ خروجی `npm audit`:
  `npm error audit Original error: loadVirtual requires existing shrinkwrap file`
- **سابقه:** PR #1 («lockfileVersion: '9.0'») در 2026-10-06 merge و سپس با PR #2 revert شده است.
- **اثر:** `npm ci` و CI ممکن نیست؛ نسخه‌های نصب‌شده بین ماشین‌ها متفاوت می‌شود.
- **توصیه:** تولید lockfile با خود npm (نه ویرایش دستی) + ثبت نتیجه `npm audit`. → قابل ترمیم توسط اجنت ۲.

### F-02 🔴 احراز هویت نمایشی + اعتبارنامه hardcoded در کد و UI
- **شواهد:** `src/App.jsx:63` → `useState({ email: 'doctor@aybak.com', password: 'admin123' })`؛ `src/App.jsx:67` → ورود با **هر** ایمیل/رمز غیرخالی (`if (form.email && form.password)`)؛ `src/App.jsx:265` → نمایش رمز `admin123` در صفحه لاگین.
- **اثر:** هیچ امنیت واقعی وجود ندارد؛ نمایش رمز در UI حتی برای دمو ضدالگو است.
- **توصیه:** ترمیم ایمن (اجنت ۲): حذف پیش‌پرکردن رمز و نمایش اعتبارنامه، افزودن بنر صریح «Demo — not real authentication». **احراز هویت واقعی = نیازمند تأیید (بالینی/حقوقی/حریم خصوصی)** — اجرا نشود.

### F-03 🟠 نبود هرگونه تست
- **شواهد:** `find src -name "*.test.*" -o -name "*.spec.*"` → `0`؛ `package.json` فاقد اسکریپت `test` و فاقد test runner.
- **توصیه:** راه‌اندازی Vitest + Testing Library و تست ماژول‌ها. → اجنت ۳ (همراه معیار پذیرش).

### F-04 🟠 نبود CI
- **شواهد:** `ls .github` → `No such file or directory`.
- **توصیه:** GitHub Actions: `npm ci` + `build` + `test` روی هر PR. → اجنت ۳ (وابسته به F-01 و F-03).

### F-05 🟡 نبود README و مستندات
- **شواهد:** `ls README*` → موجود نیست.
- **توصیه:** README دوزبانه (نصب، اجرا، هشدار دمو، ساختار). → اجنت ۲.

### F-06 🟡 تک‌فایلی بودن برنامه (monolith)
- **شواهد:** `wc -l src/App.jsx` → `545`؛ داده، auth، layout و ۶ کامپوننت صفحه همگی در یک فایل.
- **توصیه:** تفکیک به `pages/`, `components/`, `data/`, `auth/` با حفظ رفتار. → اجنت ۳ (رفاکتور ماژولار + تست).

### F-07 🟡 کنترل‌های بدون عملکرد (no-op)
- **شواهد:** `src/App.jsx:152` (Export)، `:249` (Remember me)، `:252` (Forgot password)، `:412` (+ New Booking)، `:445` (Add Patient)، `:490` (+ New Prescription) — هیچ `onClick` ندارند؛ `:536` چک‌باکس‌های Settings با `defaultChecked` و بدون ذخیره‌سازی.
- **توصیه:** بازخورد صریح «Demo action» برای دکمه‌ها + ذخیره ترجیحات غیرحساس Settings در localStorage. → اجنت ۳. موارد وابسته به auth واقعی (Remember me / Forgot password واقعی) = نیازمند تأیید.

### F-08 🟡 نبود Error Boundary
- **شواهد:** `grep -n "ErrorBoundary|componentDidCatch" src/App.jsx` → بدون نتیجه.
- **اثر:** هر خطای رندر، کل صفحه را سفید می‌کند.
- **توصیه:** افزودن ErrorBoundary با fallback. → اجنت ۳ (با تست).

### F-09 🔵 شکاف‌های دسترس‌پذیری (a11y)
- **شواهد:** `grep -rn "aria-label" src/` → `0`؛ فیلدهای ایمیل/رمز `autoComplete` ندارند (`src/App.jsx:220-243`).
- **توصیه:** `autoComplete` (اجنت ۲) + `aria-label` برای nav (اجنت ۳).

### F-10 🟠 مسدود بودن host پیش‌نمایش Arena توسط Vite
- **شواهد:** `curl http://127.0.0.1:5173/` → `HTTP 200`؛ با هدر `Host: 5173-iwgvfvozzg7fem4wbq0qn.e2b.app` →
  `Blocked request. This host (…) is not allowed. To allow this host, add … to server.allowedHosts` (HTTP 403)
- **اثر:** پیش‌نمایش زنده برای کاربر باز نمی‌شود.
- **توصیه:** افزودن `server.allowedHosts` و `preview.allowedHosts` برای `.e2b.app` در `vite.config.js`. → اجنت ۲.

### F-11 🔵 ورودی‌های تکراری/نامرتبط در .gitignore
- **شواهد:** `dist/` خطوط 6 و 46؛ `build/` خطوط 7 و 47؛ `.DS_Store` خطوط 31 و 71؛ `DockerDesktopWSL/` خط 76 (نامرتبط با پروژه وب).
- **توصیه:** فقط **پیشنهاد** پاک‌سازی توسط اجنت ۴ — حذف نشود.

### F-12 🔵 نبود LICENSE (تصمیم حقوقی)
- **شواهد:** `ls LICENSE*` → موجود نیست.
- **توصیه:** انتخاب لایسنس = **نیازمند تأیید (حقوقی)**؛ اجرا نشود.

### F-13 🟡 داده ساختگی بیمار/نسخه بدون برچسب DEMO و آمیخته با کد UI
- **شواهد:** `src/App.jsx:11-56` — آرایه‌های `patients`, `prescriptions` (نام دارو و دوز)، `appointments` و… داخل فایل UI.
- **اثر:** برای هدف «محصول واقعی»، داده ساختگی باید جدا و با برچسب صریح DEMO باشد تا با داده واقعی اشتباه نشود.
- **توصیه:** انتقال عین مقادیر به `src/data/` + برچسب «Synthetic demo data». **مقادیر بالینی (دوز، دارو) تغییر نکنند.** → اجنت ۳.

### F-14 🔵 نشست فقط در حافظه — refresh = خروج
- **شواهد:** `src/App.jsx:62` — `useState(false)` بدون هیچ ذخیره‌سازی.
- **توصیه:** برای دمو قابل قبول؛ مدیریت نشست واقعی = **نیازمند تأیید**.

## موارد نیازمند تأیید (بالینی/حقوقی — هیچ‌کدام اجرا نمی‌شوند)

1. احراز هویت/مجوزدهی واقعی، مدیریت نشست، بازیابی رمز (F-02, F-07, F-14)
2. مدل داده بیمار واقعی (PHI)، ذخیره‌سازی، رضایت‌نامه، audit log (هدف محصول واقعی)
3. هرگونه منطق نسخه‌پیچی: اعتبارسنجی دوز، تداخل دارویی، مقادیر بالینی (F-13)
4. انتخاب LICENSE و افزودن سلب مسئولیت پزشکی/شرایط استفاده (F-12)
5. تغییر هر مقدار داده بالینی دمو (نام دارو، دوز، وضعیت ریسک)

## نامشخص‌ها (سؤال از کاربر — مسدودکننده نیستند)

- **نامشخص:** زبان/جهت رابط کاربری آینده (فارسی/RTL؟) — UI فعلی انگلیسی است؛ تغییر localization تصمیم محصول است.
- **نامشخص:** پشته بک‌اند آینده (برای احراز هویت واقعی و API) — در «نیازمند تأیید» ثبت شد.
- **نامشخص:** مقصد استقرار (deploy target).

## شواهد اجرای ممیزی

```
$ npm run build            → ✓ 40 modules transformed, built in 1.21s (Vite 5.4.21)
$ curl (local)             → HTTP 200
$ curl (Arena preview host)→ HTTP 403 Blocked request
$ npm audit                → error: loadVirtual requires existing shrinkwrap file
$ git status --porcelain   → (empty — audit made no changes)
```
