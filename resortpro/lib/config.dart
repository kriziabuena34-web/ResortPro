// Supabase connection settings.
// Nandito para magamit ng main app at ng background notification check.

const supabaseUrl = 'https://dqnsolfjxsdjqmgqigyt.supabase.co';

const supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRxbnNvbGZqeHNkanFtZ3FpZ3l0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA2NjA0MDAsImV4cCI6MjEwNjIzNjQwMH0.2OBUfFFpWVl2_60oODrV6XKwAqD90FNHAYREB0N9P0k';

// ---------------------------------------------------------------------------
// Saan magbabayad ang client (ipinapakita sa booking page).
// Palitan ng tamang GCash/Maya number at pangalan ng account ng resort.
// ---------------------------------------------------------------------------
const paymentAccountName = "Aryana's Guests House";
const gcashNumber = '09628828792';
const mayaNumber = '09628828792';

/// Ilang porsyento ng total ang kailangang downpayment.
const downpaymentRate = 0.5;
