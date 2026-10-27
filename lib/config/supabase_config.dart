/// Paste your own Supabase project's values here (Supabase > Project Settings > API).
/// The key is the public "anon" / "publishable" key - it is designed to live in the app;
/// your data is protected by the Row Level Security rules in supabase_schema.sql.
/// NEVER put a "service_role" or "secret" key here.
///
/// While these still contain the placeholders, the app works fully offline and
/// simply shows "Local only".
class SupabaseConfig {
  const SupabaseConfig._();

  static const String url = 'https://llujqxrfuglatnhtotor.supabase.co';
  static const String anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxsdWpxeHJmdWdsYXRuaHRvdG9yIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY3MjMzNjIsImV4cCI6MjA5MjI5OTM2Mn0.khFRrQ3WAxhqYsP2561r1BtOZKOmkeAZ-lZXN-nynv0';

  static bool get isConfigured =>
      url.startsWith('https://') && !url.contains('YOUR_') && anonKey.length > 30 && !anonKey.contains('YOUR_');
}
