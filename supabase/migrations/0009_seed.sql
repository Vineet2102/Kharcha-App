-- Run ONCE, after creating the household.
insert into public.households (id, name) values
  ('11111111-1111-1111-1111-111111111111', 'Panicker Family')
on conflict do nothing;

insert into public.categories (id, household_id, name, kind, icon_key, colour_hex, sort_order) values
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Groceries',      'expense','shopping_cart','#4CAF50',10),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Eating Out',     'expense','restaurant',   '#FF9800',20),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Transport & Fuel','expense','local_gas_station','#795548',30),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Utilities',      'expense','bolt',         '#03A9F4',40),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Rent / EMI',     'expense','home',         '#9C27B0',50),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Medical',        'expense','local_hospital','#E91E63',60),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Education',      'expense','school',       '#3F51B5',70),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Shopping',       'expense','shopping_bag', '#F44336',80),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Entertainment',  'expense','movie',        '#009688',90),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Household Help', 'expense','cleaning_services','#8BC34A',100),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Gifts & Festivals','expense','card_giftcard','#FFC107',110),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Subscriptions',  'expense','subscriptions','#673AB7',120),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Travel',         'expense','flight',       '#00BCD4',130),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Insurance',      'expense','shield',       '#607D8B',140),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Miscellaneous',  'expense','more_horiz',   '#9E9E9E',999),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Salary',         'income','payments',      '#4CAF50',10),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Business',       'income','business',      '#3F51B5',20),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Interest & Dividends','income','savings',  '#009688',30),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Rent Received',  'income','apartment',     '#795548',40),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Other Income',   'income','more_horiz',    '#9E9E9E',999);

insert into public.payment_methods (id, household_id, name, type, sort_order) values
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Cash',        'cash',  10),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','UPI',         'upi',   20),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Credit Card', 'card',  30),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Debit Card',  'card',  40),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Net Banking', 'bank',  50),
  (gen_random_uuid(),'11111111-1111-1111-1111-111111111111','Wallet',      'wallet',60);
