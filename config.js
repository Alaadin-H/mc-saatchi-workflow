/**
 * ============================================================================
 * PRODUCTION TASK BOARD - APPLICATION CONFIGURATION
 * ============================================================================
 * يمكنك وضع بيانات Supabase هنا مباشرة، أو إدخالها من واجهة الموقع
 * من زر "Supabase Setup / الإعدادات" في أعلى الشاشة وسيتم حفظها في المتصفح.
 * ============================================================================
 */

window.SUPABASE_CONFIG = {
  // رابط مشروع Supabase المباشر
  url: 'https://ldsevaytazsnfvsdxrno.supabase.co',

  // مفتاح anon public key
  anonKey: 'sb_publishable_W2y6fRzN9rJRN_Gn0wRXBA_dD4ybYRv'
};

// القيم الافتراضية للقوائم المنسدلة (مطابقة لنظام Google Apps Script الأصلي)
window.DEFAULT_CONFIG = {
  taskTypes: [
    "Photos", "Video", "Design", "Carousel Photos",
    "Carousel Video", "Match Coverage", "Script", "Presentation"
  ],
  graphicSizes: [
    "Reel 9:16", "Wide 16:9", "Square 1:1", "Portrait 3:4", "Portrait 4:5"
  ],
  clients: [
    "MINNOWS", "Palm Hills", "APT Padel", "Potential Client / Pitching"
  ],
  priorities: [
    "Low", "Medium", "High", "Urgent"
  ],
  statuses: [
    "Not Started", "Work in Progress", "Submitted for Review", "Completed"
  ],
  taskCategories: [
    "New Task", "Existing Task"
  ],
  departments: [
    "Social", "Marketing"
  ]
};
