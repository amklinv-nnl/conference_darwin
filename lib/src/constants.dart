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
  "keynote": <String>[],
  "lunch": ["break"],
  "poster": ["coffee", "short"],
  "default": <String>[]
};
