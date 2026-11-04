# 02 — Repair Report | گزارش ترمیم (اجنت ۲)

- **Input / ورودی:** فقط `handoff/01-audit.md`
- **Branch / برنچ:** `arena/90bc4b95-aybak-hospital-platform` (طبق تأیید مرحله ۰؛ معادل `fix/…`)
- **Date / تاریخ:** 2026-11-05
- **Scope rule / قاعده دامنه:** فقط موارد ثبت‌شده در ممیزی با شواهد؛ هیچ داده واقعی/secret؛ هیچ تغییر بالینی/حقوقی اجرا نشد.

## English summary

Four safe, evidence-backed repairs applied: (R-01) Vite dev/preview `allowedHosts` fix — Arena preview now returns HTTP 200; (R-02) removed hardcoded credentials from state and UI, added honest demo-mode notice and `autoComplete` attributes — login logic intentionally unchanged; (R-03) generated `package-lock.json` via npm, verified `npm ci`, recorded `npm audit` (2 dev-server-only vulnerabilities; fix requires a breaking Vite major upgrade → deferred for approval); (R-04) bilingual README. Build passes. Modularization, tests, CI, error boundary, demo-action feedback and data separation are handed to Agent 3 as leftovers.

## تغییرات

### R-01 — رفع مسدودی host پیش‌نمایش (F-10)
- **دلیل:** ممیزی نشان داد هاست پیش‌نمایش Arena با HTTP 403 مسدود می‌شود.
- **فایل‌ها:** `vite.config.js` — افزودن `server.allowedHosts: ['.e2b.app']` و `preview.allowedHosts: ['.e2b.app']` (فقط dev/preview؛ بی‌اثر بر build پروداکشن).
- **نتیجه:** `curl` با هدر Host پیش‌نمایش → **HTTP 200** (قبلاً 403). هشدار preview در ابزار اجرا نیز برطرف شد.

### R-02 — حذف اعتبارنامه hardcoded + برچسب صادقانه دمو (F-02 بخش ایمن، F-09 بخش autoComplete)
- **دلیل:** رمز `admin123` در کد پیش‌پر و در UI نمایش داده می‌شد؛ ضدالگوی امنیتی حتی برای دمو.
- **فایل‌ها:** `src/App.jsx`
  - state فرم لاگین از مقادیر پیش‌پر به `{ email: '', password: '' }` تغییر کرد.
  - جعبه «Demo credentials: … / admin123» با بنر صریح جایگزین شد: «Demo mode: any email and password… not real authentication… Not for clinical use.»
  - `autoComplete="email"` و `autoComplete="current-password"` اضافه شد.
- **عمداً تغییر نکرد:** منطق ورود (هر مقدار غیرخالی) — احراز هویت واقعی نیازمند تأیید است.
- **نتیجه:** build موفق؛ `grep admin123` در ماژول سروشده = **0**.

### R-03 — تولید lockfile و ثبت وضعیت امنیتی وابستگی‌ها (F-01)
- **دلیل:** بدون lockfile، `npm ci` و `npm audit` ممکن نبود (شواهد ممیزی). سابقه: PR #1/#2 (افزودن/برگرداندن دستی lockfile) — این بار lockfile **توسط خود npm** تولید شد، نه ویرایش دستی.
- **فایل‌ها:** `package-lock.json` (جدید، npm 10.9.8، lockfileVersion 3).
- **نتیجه:** `npm ci` → `added 80 packages in 3s` ✅؛ build موفق ✅.
- **خروجی `npm audit`:** `2 vulnerabilities (1 moderate, 1 high)` — esbuild ≤0.24.2 (GHSA-67mh-4wv8-2f99، فقط dev-server) و vite ≤6.4.3 وابسته به آن. رفع، نیازمند ارتقای شکسته به vite@8.3.5 است → **اجرا نشد** (بخش نیازمند تأیید را ببینید).

### R-04 — افزودن README دوزبانه (F-05)
- **دلیل:** مخزن هیچ مستنداتی نداشت.
- **فایل‌ها:** `README.md` (جدید) — شروع سریع، ساختار، هشدار دمو، قواعد ایمنی، فهرست مستندات handoff، وضعیت لایسنس (تصمیم‌نگرفته).
- **نتیجه:** فایل ساخته شد؛ ارجاعات به `npm test` و ساختار ماژولار پس از مرحله ۳ کامل می‌شود (در همان PR).

## باقی‌مانده (→ ورودی اجنت ۳)

| # | مورد | منشأ در ممیزی | معیار پذیرش پیشنهادی |
|---|------|----------------|------------------------|
| L-01 | راه‌اندازی Vitest + Testing Library و تست ماژول‌ها | F-03 | `npm test` سبز؛ پوشش مسیرهای ورود/خروج و ناوبری |
| L-02 | CI (GitHub Actions): `npm ci` + build + test روی PR | F-04 | workflow معتبر؛ اجرای سبز روی PR |
| L-03 | تفکیک `App.jsx` به `pages/`, `components/`, `data/`, `auth/` با حفظ رفتار | F-06 | همه مسیرها و UI فعلی حفظ شوند؛ تست‌ها سبز |
| L-04 | بازخورد صریح «Demo action» برای دکمه‌های no-op + ذخیره ترجیحات غیرحساس Settings در localStorage | F-07 | کلیک → پیام قابل مشاهده؛ ترجیحات پس از reload حفظ شوند |
| L-05 | ErrorBoundary با fallback + تست | F-08 | خطای رندر → پیام خطا به‌جای صفحه سفید |
| L-06 | `aria-label` برای ناوبری | F-09 | nav قابل شناسایی برای screen reader |
| L-07 | جداسازی داده ساختگی به `src/data/` با برچسب «Synthetic DEMO» — **مقادیر بالینی عیناً حفظ شوند** | F-13 | داده‌ها بدون تغییر مقدار منتقل شوند؛ برچسب DEMO در UI بیماران/نسخه‌ها |

## نیازمند تأیید (اجرا نشد)

1. **احراز هویت واقعی** (بالینی/حقوقی/حریم خصوصی): اعتبارسنجی واقعی، نشست، Remember me، Forgot password — F-02/F-07/F-14.
2. **داده واقعی بیمار (PHI):** مدل، ذخیره‌سازی، رضایت، audit log — هدف «محصول واقعی».
3. **منطق بالینی نسخه‌ها:** اعتبارسنجی دوز/تداخل دارویی؛ هیچ مقدار دارو/دوز دمو تغییر نکرد — F-13.
4. **LICENSE و سلب مسئولیت پزشکی** (حقوقی) — F-12.
5. **ارتقای شکسته Vite 5 → 8** (تصمیم فنی پرریسک): تنها راه رفع آسیب‌پذیری‌های dev-server گزارش‌شده در R-03؛ نیازمند تأیید کاربر و بررسی سازگاری pluginها.
6. **بومی‌سازی UI (فارسی/RTL)** — نامشخص؛ تصمیم محصول.

## شواهد اجرا

```
$ npm install            → package-lock.json created (29,121 bytes, lockfileVersion 3)
$ npm ci                 → added 80 packages in 3s                      ✅
$ npm run build          → ✓ 40 modules transformed, built in 1.20s     ✅
$ npm audit              → 2 vulnerabilities (1 moderate, 1 high) — dev-server only; breaking fix deferred
$ curl (preview host)    → HTTP 200 (was 403)                           ✅
$ grep -c admin123 (served /src/App.jsx) → 0                            ✅
```

**Files changed in this stage:** `vite.config.js`, `src/App.jsx`, `package-lock.json` (new), `README.md` (new), `handoff/02-repair.md` (this report).
