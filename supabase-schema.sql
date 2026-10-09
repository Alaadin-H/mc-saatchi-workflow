-- ============================================================================
-- PRODUCTION TASK BOARD - SUPABASE DATABASE SCHEMA
-- ============================================================================
-- قم بنسخ هذا الكود بالكامل ولصقه في SQL Editor داخل لوحة تحكم Supabase
-- ثم اضغط على RUN لإنشاء الجداول والقواعد والبيانات التجريبية
-- ============================================================================

-- 1. تسلسل إنشاء Task ID تلقائياً (T-0001, T-0002, ...)
CREATE SEQUENCE IF NOT EXISTS task_id_seq START 1;

CREATE OR REPLACE FUNCTION generate_task_id()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.task_id IS NULL OR NEW.task_id = '' THEN
    NEW.task_id := 'T-' || LPAD(nextval('task_id_seq')::text, 4, '0');
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2. جدول المهام الرئيسي (24 عمود متوافق مع نظام Google Sheets الأصلي)
CREATE TABLE IF NOT EXISTS tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id TEXT UNIQUE NOT NULL,
  task_name TEXT NOT NULL,
  description TEXT DEFAULT '',
  copy_message TEXT DEFAULT '',
  owner TEXT DEFAULT '',
  task_type TEXT DEFAULT 'Design',
  graphic_size TEXT DEFAULT 'Wide 16:9',
  client TEXT DEFAULT 'MINNOWS',
  submitted_date TIMESTAMPTZ DEFAULT now(),
  due_date DATE,
  posting_date DATE,
  priority TEXT DEFAULT 'Medium',
  assigned_to TEXT DEFAULT '',
  status TEXT DEFAULT 'Not Started',
  brand_guideline_link TEXT DEFAULT '',
  brand_guideline_note TEXT DEFAULT '',
  reference_link TEXT DEFAULT '',
  reference_note TEXT DEFAULT '',
  source_link TEXT DEFAULT '',
  source_note TEXT DEFAULT '',
  finished_link TEXT DEFAULT '',
  finished_note TEXT DEFAULT '',
  task_category TEXT DEFAULT 'New Task',
  department TEXT DEFAULT 'Social',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- ربط تريجر توليد رقم المهمة التلقائي
DROP TRIGGER IF EXISTS trigger_generate_task_id ON tasks;
CREATE TRIGGER trigger_generate_task_id
BEFORE INSERT ON tasks
FOR EACH ROW
EXECUTE FUNCTION generate_task_id();

-- 3. تريجر تحديث updated_at تلقائياً
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_tasks_updated_at ON tasks;
CREATE TRIGGER trigger_update_tasks_updated_at
BEFORE UPDATE ON tasks
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

-- 4. إعدادات الخيارات والقوائم المنسدلة (Dropdown Settings)
CREATE TABLE IF NOT EXISTS app_settings (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL
);

INSERT INTO app_settings (key, value) VALUES
('dropdowns', '{
  "taskTypes": ["Photos", "Video", "Design", "Carousel Photos", "Carousel Video", "Match Coverage", "Script", "Presentation"],
  "graphicSizes": ["Reel 9:16", "Wide 16:9", "Square 1:1", "Portrait 3:4", "Portrait 4:5"],
  "clients": ["MINNOWS", "Palm Hills", "APT Padel", "Potential Client / Pitching"],
  "priorities": ["Low", "Medium", "High", "Urgent"],
  "statuses": ["Not Started", "Work in Progress", "Submitted for Review", "Completed"],
  "taskCategories": ["New Task", "Existing Task"],
  "departments": ["Social", "Marketing"]
}'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- 5. تفعيل أمان مستوى الصفوف (Row Level Security - RLS)
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_settings ENABLE ROW LEVEL SECURITY;

-- سياسات الوصول العام عبر مفتاح Anon Key (قراءة وإضافة وتعديل وحذف)
DROP POLICY IF EXISTS "Allow public read access" ON tasks;
CREATE POLICY "Allow public read access" ON tasks FOR SELECT USING (true);

DROP POLICY IF EXISTS "Allow public insert access" ON tasks;
CREATE POLICY "Allow public insert access" ON tasks FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Allow public update access" ON tasks;
CREATE POLICY "Allow public update access" ON tasks FOR UPDATE USING (true);

DROP POLICY IF EXISTS "Allow public delete access" ON tasks;
CREATE POLICY "Allow public delete access" ON tasks FOR DELETE USING (true);

DROP POLICY IF EXISTS "Allow public read app_settings" ON app_settings;
CREATE POLICY "Allow public read app_settings" ON app_settings FOR SELECT USING (true);

DROP POLICY IF EXISTS "Allow public manage app_settings" ON app_settings;
CREATE POLICY "Allow public manage app_settings" ON app_settings FOR ALL USING (true);

-- 6. تفعيل التحديث الفوري المباشر (Supabase Realtime)
-- حتى تتحدث الشاشات فوراً عند إضافة أو تعديل أي مهمة
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND tablename = 'tasks'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE tasks;
  END IF;
END $$;

-- 7. إضافة بيانات تجريبية أولية (Sample Initial Data)
INSERT INTO tasks (
  task_name, description, copy_message, department, task_category,
  owner, assigned_to, client, task_type, graphic_size,
  priority, status, due_date, posting_date,
  brand_guideline_link, reference_link, source_link, finished_link
) VALUES
(
  'Summer Campaign Teaser Reel',
  'Create an energetic 15s teaser for the upcoming summer tournament.',
  'Get ready for the biggest padel showdown this summer! 🎾🔥',
  'Social', 'New Task', 'Ahmed Salem', 'Karim Omar', 'APT Padel', 'Reel 9:16', 'Reel 9:16',
  'Urgent', 'Work in Progress', CURRENT_DATE + INTERVAL '2 days', CURRENT_DATE + INTERVAL '4 days',
  'https://drive.google.com', 'https://instagram.com', 'https://dropbox.com', ''
),
(
  'Palm Hills Community Match Coverage',
  'Edit 4 photo highlights and 1 recap carousel from yesterday’s community match.',
  'Unforgettable moments on the court today! 🌟',
  'Marketing', 'Existing Task', 'Sara Nabil', 'Mona Zaki', 'Palm Hills', 'Carousel Photos', 'Square 1:1',
  'High', 'Submitted for Review', CURRENT_DATE + INTERVAL '1 days', CURRENT_DATE + INTERVAL '3 days',
  'https://drive.google.com', '', 'https://drive.google.com/folder', 'https://drive.google.com/drafts'
),
(
  'Minnows Brand Launch Graphic',
  'Main banner design for Minnows product launch campaign across digital ads.',
  'Pure freshness in every drop. Discover Minnows now.',
  'Social', 'New Task', 'Alaadin', 'Tamer Hosny', 'MINNOWS', 'Design', 'Wide 16:9',
  'Medium', 'Not Started', CURRENT_DATE + INTERVAL '5 days', CURRENT_DATE + INTERVAL '7 days',
  'https://brand.minnows.com', 'https://pinterest.com', '', ''
),
(
  'Sponsorship Presentation Pitch Deck',
  'Prepare the 12-slide pitch deck for prospective partners.',
  '',
  'Marketing', 'New Task', 'Sara Nabil', 'Ahmed Salem', 'Potential Client / Pitching', 'Presentation', 'Wide 16:9',
  'Low', 'Completed', CURRENT_DATE - INTERVAL '1 days', CURRENT_DATE + INTERVAL '10 days',
  '', '', 'https://drive.google.com', 'https://canva.com'
)
ON CONFLICT DO NOTHING;
