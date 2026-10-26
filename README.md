# 📋 MC Saatchi Workflow (Supabase + GitHub)

نظام إدارة ومتابعة مهام المحتوى والإعلانات (**MC Saatchi Workflow**) مبني كبديل حديث وسريع ومستقل لنظام Google Sheets القديم، باستخدام قاعدة بيانات **Supabase (PostgreSQL)** واستضافة سحابية مجانية عبر **GitHub Pages**.

---

## 🚀 المميزات الرئيسية (Features)

1. **نفس الحقول والبيانات بالكامل (24 عمود/خاصية)**:
   - Task ID (توليد تلقائي تسلسلي مثل `T-0001`, `T-0002` عبر Database Trigger).
   - Task Name, Description, Copy Message, Department, Category.
   - Owner, Assigned To, Client, Task Type, Graphic Size, Priority, Status.
   - Due Date & Posting Date (مع تنبيه المهام المتأخرة Overdue تلقائياً).
   - روابط وملاحظات Brand Guideline, References, Source Materials, Finished Task.

2. **3 طرق عرض تفاعلية**:
   - **Board View (Kanban)**: بطاقات مهام مع السحب والإفلات (Drag & Drop) مع إمكانية تغيير الحالة فوراً.
   - **Table View**: جدول كامل مع إمكانية الترتيب (Sorting) بالنقر على رؤوس الأعمدة، مع روابط مباشرة لمواد العمل.
   - **Timeline View**: جدول زمني مرتب حسب تاريخ التسليم أو تاريخ النشر مع وسم المهام العاجلة.

3. **تحديث فوري مباشر (Supabase Realtime)**:
   - أي تعديل أو سحب مهمة من أي عضو في الفريق يظهر لباقي الفريق مباشرة على الشاشة بدون إعادة تحميل الصفحة!

4. **إحصائيات وفلاتر ذكية**:
   - إحصائيات علوية (إجمالي المهام، قيد التنفيذ، قيد المراجعة، المكتملة، المتأخرة).
   - فلاتر للبحث النصي وتصفية المهام بالعميل، القسم، النوع، الحالة، الأولوية، والمسؤول.

5. **وضع تجريبي فوري (Demo Mode)**:
   - يعمل الموقع محلياً ببيانات تجريبية حتى قبل إدخال بيانات Supabase.

---

## 🛠️ خطوات التشغيل والربط مع Supabase (خلال دقيقتين)

### 1. إنشاء مشروع على Supabase
1. ادخل على [Supabase.com](https://supabase.com) وسجّل دخولك بحسابك مجاناً.
2. اضغط على **"New Project"** واختر اسم المشروع وكلمة المرور.

### 2. تنفيذ كود قاعدة البيانات (Database Schema)
1. من القائمة الجانبية في لوحة Supabase، افتح **SQL Editor**.
2. افتح ملف `supabase-schema.sql` الموجود في هذا المشروع وانسخ محتواه بالكامل.
3. الصق الكود داخل **SQL Editor** ثم اضغط على زر **RUN** في الأسفل.
   *(سيتم إنشاء جدول المهام `tasks`، والتسلسل التلقائي `T-0001`، وسياسات الأمان RLS، والتحديث الفوري Realtime، وبيانات تجريبية أولية).*

### 3. الحصول على مفاتيح الربط (API Keys)
1. من القائمة الجانبية في Supabase اضغط على **Project Settings** (أيقونة الترس ⚙️) ثم **API**.
2. ستجد:
   - **Project URL** (مثل: `https://abcdefghijklm.supabase.co`)
   - **Project API keys -> `anon` `public`**

### 4. ربط الموقع بـ Supabase
لديك طريقتان سهلتان:
- **الطريقة الأولى (من واجهة الموقع مباشرة)**:
  افتح `index.html` في المتصفح، واضغط على زر **⚙️ Settings** في أعلى الصفحة، ثم الصق الـ **Project URL** و **Anon Key** واضغط **Save & Connect**.
- **الطريقة الثانية (من ملف الإعدادات)**:
  افتح ملف `config.js` والصق الـ `url` والـ `anonKey` هناك ليتم استخدامها تلقائياً لكل من يفتح الموقع.

---

## 🌐 خطوات رفع الموقع على GitHub وتشغيله مجاناً (GitHub Pages)

### الخطوة 1: تهيئة Git وإنشاء المستودع
قم بفتح سطر الأوامر (Terminal / PowerShell) في مجلد المشروع ونفّذ الأوامر التالية:

```bash
git init
git add .
git commit -m "Initial commit: Production Task Board with Supabase"
```

### الخطوة 2: ربطه بمستودع GitHub
1. ادخل على [GitHub.com](https://github.com) وأنشئ مستودعاً جديداً (**New Repository**) باسم مثلاً `production-task-board`.
2. انسخ رابط المستودع ونفّذ الأوامر التالية (مع استبدال الرابط برابطك):

```bash
git branch -M main
git remote add origin https://github.com/USERNAME/production-task-board.git
git push -u origin main
```

### الخطوة 3: تفعيل الاستضافة المجانية (GitHub Pages)
1. في صفحة المستودع على GitHub، اضغط على تبويب **Settings**.
2. من القائمة الجانبية اضغط على **Pages**.
3. تحت قسم **Build and deployment -> Branch**:
   - اختر فرع `main`.
   - اختر المجلد `/ (root)`.
   - اضغط **Save**.
4. خلال دقيقة سيظهر لك رابط موقعك الحي المنشور مجاناً مثل:
   `https://USERNAME.github.io/production-task-board/`

---

## 📁 هيكلية ملفات المشروع (Project Structure)

```text
production-task-board/
│── index.html              # الصفحة الرئيسية وواجهة المستخدم
│── style.css               # التصميم والتنسيقات الكاملة
│── app.js                  # منطق التطبيق والتفاعل مع Supabase و Realtime
│── config.js               # إعدادات Supabase والخيارات الافتراضية
│── supabase-schema.sql     # سكريبت إنشاء قاعدة البيانات والتريجرز والسياسات
│── .gitignore              # ملف استثناء الملفات غير المرغوبة في Git
└── README.md               # دليل التشغيل والتوثيق
```

---

## 💡 نصائح إضافية
- لتخصيص الخيارات الافتراضية للقوائم المنسدلة (العملاء، الأقسام، إلخ)، يمكنك تعديلها من `config.js` أو من جدول `app_settings` في Supabase مباشرة.
- الموقع مصمم بتقنية Pure HTML/CSS/JS ولا يحتاج إلى أي أدوات تثبيت أو build steps معقدة، ويعمل فوراً بمجرد فتح `index.html` أو رفعه على أي استضافة (GitHub Pages, Netlify, Vercel).


## ✎ قسم التعديلات (Edits)

كل تاسك فيه قسم **Edits** مقفول افتراضيًا. بيحتوي على أي عدد من التعديلات، وكل تعديل فيه:
Owner Note (ملاحظات صاحب التاسك) · New Delivery Link (لينك التسليم الجديد) · My Note (ملاحظتك).

لتفعيله: شغّل ملف `supabase-add-revisions.sql` مرة واحدة في SQL Editor.
