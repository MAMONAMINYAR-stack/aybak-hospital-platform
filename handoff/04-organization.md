# 04 — Organization Report | گزارش سازمان‌دهی (اجنت ۴)

- **Input / ورودی:** همه فایل‌های `handoff/` (00 تا 03) + بررسی فقط‌خواندنی مخزن
- **Branch / برنچ:** `arena/90bc4b95-aybak-hospital-platform` — تحویل فقط با PR؛ merge با کاربر.
- **Date / تاریخ:** 2026-11-05
- **Compliance / انطباق:** ⛔ هیچ فایلی حذف، جابه‌جا یا بازنویسی نشد. تنها فایل جدیدِ این مرحله همین گزارش است. همه موارد زیر **فقط پیشنهاد** هستند.

## English summary

After the stage-3 refactor the repository already follows a standard React/Vite layout, so this report proposes **no mandatory moves**. It lists 4 duplicate/irrelevant `.gitignore` entries, 2 unused/inconsistent demo-data items, and 5 missing hygiene artifacts (favicon, engines field, lint tooling, LICENSE, PR template/CODEOWNERS) — each with evidence and a proposal. Nothing was deleted or rewritten; every action requires maintainer approval. One evidence correction to the audit is recorded (F-11 line number).

## ۱) ساختار استاندارد پیشنهادی

وضعیت فعلی (پس از مرحله ۳) تقریباً استاندارد است. ساختار هدف با افزوده‌های **پیشنهادی** (★ = جدید، فقط پیشنهاد):

```
aybak-hospital-platform/
├── .github/
│   ├── workflows/ci.yml              # موجود (مرحله ۳)
│   ├── PULL_REQUEST_TEMPLATE.md      # ★ پیشنهاد
│   └── CODEOWNERS                    # ★ پیشنهاد — نیازمند تأیید
├── docs/                             # ★ پیشنهاد — راهنماهای آینده (معماری، تصمیم fa/RTL، طرح بک‌اند)
├── handoff/                          # حفظ شود — دفتر فرایند زنجیره (00..04)
├── public/                           # ★ پیشنهاد — favicon.svg و assetهای ثابت
├── src/
│   ├── auth/                         # موجود — demo auth
│   ├── components/                   # موجود — UI مشترک
│   ├── data/                         # موجود — فقط داده ساختگی DEMO
│   ├── pages/                        # موجود — یک ماژول per صفحه
│   ├── test/                         # موجود — setup تست
│   ├── App.jsx, App.test.jsx         # موجود — تست‌ها هم‌مکان (قرارداد Vitest) حفظ شوند
│   ├── main.jsx, index.css
├── index.html
├── package.json, package-lock.json
├── vite.config.js
├── README.md
└── LICENSE                           # ★ پیشنهاد — فقط پس از تأیید حقوقی (F-12)
```

## ۲) نگاشت جابه‌جایی‌ها (مسیر فعلی ← مسیر پیشنهادی)

| مسیر فعلی | پیشنهاد | دلیل |
|-----------|---------|------|
| همه فایل‌های موجود | **بدون جابه‌جایی** | ساختار پس از مرحله ۳ استاندارد است؛ جابه‌جایی بی‌مورد ریسک import دارد |
| `handoff/*.md` | حفظ در ریشه | قرارداد زنجیره به مسیر `handoff/` ارجاع می‌دهد؛ انتقال به `docs/` قرارداد را می‌شکند |
| تست‌های `src/**/*.test.*` | حفظ هم‌مکان | قرارداد رایج Vitest؛ پوشه `tests/` جداگانه لازم نیست |
| (فایل جدید) | `docs/`, `public/`, `.github/PULL_REQUEST_TEMPLATE.md` | فقط افزوده‌های آینده، نه جابه‌جایی |

## ۳) فهرست تکراری / بی‌استفاده — با شواهد (فقط پیشنهاد؛ حذف نشد)

| # | مورد | شواهد | پیشنهاد |
|---|------|-------|---------|
| D-01 | `dist/` تکراری در .gitignore | خطوط **6** و **46** | حذف خط 46 پس از تأیید |
| D-02 | `build/` تکراری | خطوط **7** و **47** | حذف خط 47 پس از تأیید |
| D-03 | `.DS_Store` تکراری | خطوط **31** و **71** | حذف خط 71 پس از تأیید |
| D-04 | `DockerDesktopWSL/` نامرتبط با پروژه وب | خط **73** (تصحیح شواهد F-11 که 76 نوشته بود) | حذف پس از تأیید |
| U-01 | فیلد `active` در `schedule` هرگز خوانده نمی‌شود | `src/data/demoData.js:36-41` تعریف؛ `src/pages/DashboardPage.jsx:73` فقط `.day` را می‌خواند | حذف فیلد یا استفاده از آن — چون داده دمو است، نیازمند تأیید |
| U-02 | ناسازگاری نمودار: ۷ میله ولی ۶ روز | `DashboardPage.jsx:67` → `[52,68,74,55,84,92,61]` (۷ مقدار)؛ `demoData.js` → ۶ روز (میله هفتم بی‌برچسب) | هم‌ترازی (افزودن Sun یا حذف میله هفتم) — تغییر داده دمو، نیازمند تأیید؛ توجه: تست `demoData.test.js` طول ۶ را assert می‌کند |
| U-03 | `IS_DEMO_DATA` فقط در تست ارجاع می‌شود | `grep` → صرفاً `demoData.js` و `demoData.test.js` | **حفظ شود** — پرچم ایمنی عمدی است، نه کد مرده |
| M-01 | نبود favicon/public | `ls public` → موجود نیست؛ `grep favicon index.html` → 0 | افزودن `public/favicon.svg` + link در index.html |
| M-02 | نبود `engines` در package.json | فیلد engines غایب؛ CI از Node 22 استفاده می‌کند | افزودن `"engines": { "node": ">=20" }` |
| M-03 | نبود lint/format | ESLint/Prettier در devDeps غایب | task جداگانه با تأیید (ممکن است هشدارهای زیادی تولید کند) |
| M-04 | نبود LICENSE | `ls LICENSE*` → غایب (F-12) | تصمیم حقوقی کاربر |
| M-05 | نبود PR template / CODEOWNERS / branch protection | `.github/` فقط ci.yml دارد | افزودن template و CODEOWNERS؛ **branch protection روی main تنظیم GitHub و اقدام کاربر است** |

**بهداشت فعلی (مثبت):** ۳۲ فایل tracked؛ `git ls-files dist node_modules` → 0 (خروجی build و وابستگی‌ها کامیت نشده‌اند) ✅

## ۴) ریسک‌ها و وابستگی‌ها

- حذف خطوط .gitignore کم‌ریسک است ولی باید پس از آن `git status` بررسی شود تا فایل ناخواسته‌ای track نشود.
- U-01/U-02 داده دمو را لمس می‌کنند → تست قفل‌کننده (`demoData.test.js`) باید هم‌زمان به‌روز شود؛ فقط با تأیید کاربر.
- هر جابه‌جایی آینده فایل‌ها → به‌روزرسانی importها + اجرای مجدد تست/CI الزامی است.
- افزودن lint ممکن است حجم تغییرات جداگانه‌ای بسازد؛ نباید با این PR مخلوط شود.
- `handoff/` سند فرایند است؛ فشرده‌سازی/انتقال آن پیش از پایان زنجیره توصیه نمی‌شود.

## ۵) نیازمند تأیید

1. اجرای حذف‌های D-01..D-04 و U-01/U-02 (هیچ‌کدام اجرا نشد).
2. LICENSE و سلب مسئولیت پزشکی (حقوقی — تکرار از 01/02/03).
3. CODEOWNERS و branch protection روی `main` (اقدام کاربر در GitHub).
4. افزودن ابزار lint/format و `engines` (وابستگی/پیکربندی جدید).
5. بومی‌سازی UI فارسی/RTL (تصمیم محصول — نامشخص).
