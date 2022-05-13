// Start at 8:30 AM on February 27, 2023
final START_TIME = new DateTime.utc(2023, 2, 27, 8, 30);

// End at 1:30 PM on March 3, 2023
final END_TIME = new DateTime.utc(2023, 3, 3, 13, 30);

// DateTime rounds down, so we add 1
final NUM_DAYS = END_TIME.difference(START_TIME).inDays + 1;

// Whether to treat the final day as a half day (no lunch, 1 coffee break)
final bool FINAL_HALF_DAY = true;

final int COFFEE_LENGTH = 30;
final int LUNCH_LENGTH = 90;
final int SHORT_LENGTH = 5;

final Map DURATIONS = {
  "minisymposium": 100,
  "keynote": 75,
  "lunch": LUNCH_LENGTH,
  "poster": 120,
  "default": 30
};

final Map TAGS = {
  "minisymposium": ["minisymposium"],
  "keynote": ["keynote"],
  "lunch": ["lunch", "break", "not_final_day"],
  "poster": ["poster", "day_end", "not_final_day"],
  "default": <String>[]
};

final Map SEEK = {
  "minisymposium": ["break"],
  "keynote": ["break"],
  "lunch": <String>[],
  "poster": <String>[],
  "default": <String>[]
};

final Map AVOID = {
  "minisymposium": <String>[],
  "keynote": <String>["keynote"],
  "lunch": ["break"],
  "poster": ["coffee", "short"],
  "default": <String>[]
};

// Penalties
final MISSING_SESSION = 256.0;
final MISSING_MINISYMPOSIUM = 128.0;
final WRONG_DAY_COUNT = 1.0;
final POSTERS_SEPARATED = 1.0;
final MULTIPLE_POSTERS_PER_DAY = 1.0;
final EMPTY_DAY = 1.0;
final SESSION_TOO_EARLY = 128.0;
final WRONG_NUM_LUNCHES = 16.0;
final DAY_TOO_LONG = 1.0;
final TOO_THIRSTY = 1.0;
final WRONG_NUM_COFFEE = 1.0;
final WRONG_NUM_KEYNOTE = 8.0;
final WRONG_TIME_KEYNOTE = 64.0;
final TOO_HUNGRY = 1.0;
final FAIL_TO_AVOID = 32.0;
final GOOD_SEEK = 1.0;
final BLOCK_TOO_LONG = 1.0;
final LAST_DAY_LONG = 8.0;
final GOOD_FINAL_DAY_SESSION = 1.0;
final BAD_FINAL_DAY_SESSION = 1.0;
final BAD_LUNCH_TIME = 2.0;
