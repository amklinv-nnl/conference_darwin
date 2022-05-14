import 'dart:async';
import 'dart:math';
import 'package:conference_darwin/src/baked_schedule.dart';
import 'package:conference_darwin/src/constants.dart';
import 'package:conference_darwin/src/schedule_phenotype.dart';
import 'package:conference_darwin/src/session.dart';
import 'package:darwin/darwin.dart';

class ScheduleEvaluator
    extends PhenotypeEvaluator<Schedule, int, ScheduleEvaluatorPenalty> {
  static const _lunchHourMin = 11;

  static const _lunchHourMax = 13;

  final List<Session> sessions;

  final int maxMinutesWithoutBreak = 120;

  final int maxMinutesWithoutLargeMeal = 6 * 60;

  final int maxMinutesWithoutDrink = 3 * 60;

  final int maxMinutesInDay = 9 * 60;

  final int targetLunchesPerDay = 1;

  ScheduleEvaluator(this.sessions);

  @override
  Future<ScheduleEvaluatorPenalty> evaluate(Schedule phenotype) {
    return new Future.value(internalEvaluate(phenotype));
  }

  ScheduleEvaluatorPenalty internalEvaluate(Schedule phenotype,
      {bool verbose: false}) {
    final penalty = new ScheduleEvaluatorPenalty();

    final ordered = phenotype.getOrdered(sessions);

    // Make sure all desired sessions are in the program
    for (final session in sessions) {
      if (!ordered.contains(session)) {
        if (verbose)
          print(session.name + " was left out of the program entirely\n");

        // Missing minisymposia are only worth 200, the rest 500
        if (session.isMinisymposium)
          penalty.constraints += MISSING_MINISYMPOSIUM;
        else
          penalty.constraints += MISSING_SESSION;
      }
    }

    // Make sure conference is the correct number of days
    final days = phenotype.getDays(ordered, sessions).toList(growable: false);
    penalty.constraints += (NUM_DAYS - days.length).abs() * WRONG_DAY_COUNT;
    if (verbose && days.length != NUM_DAYS)
      print("conference lasts ${days.length} of $NUM_DAYS days\n");

    // Gumband the poster sessions together
    bool sawPoster = false;
    var potentialPenalty = 0.0;
    for (final day in days) {
      var nPosterToday = day.where((s) => s.isPoster).length;
      if (nPosterToday > 0) {
        sawPoster = true;
        penalty.constraints += potentialPenalty;
        if (verbose && potentialPenalty > 0)
          print("Poster sessions are separated\n");
      } else if (sawPoster) potentialPenalty += POSTERS_SEPARATED;

      // Too many poster sessions in one day
      if (nPosterToday > 1) {
        penalty.constraints += MULTIPLE_POSTERS_PER_DAY;
        if (verbose) print("Too many posters in one day: $nPosterToday\n");
      }
    }

    int dayNumber = 0;
    for (final day in days) {
      dayNumber += 1;

      // Make sure no day is empty
      if (day.isEmpty) {
        if (verbose) print("Day $day is empty\n");
        penalty.cultural += EMPTY_DAY;
        continue;
      }

      // Make sure end day sessions actually end the day
      for (final dayEndSession in day.where((s) => s.isDayEnd)) {
        penalty.constraints +=
            SESSION_TOO_EARLY * (day.length - day.indexOf(dayEndSession) - 1);
        if (verbose && day.indexOf(dayEndSession) < day.length - 1)
          print(
              "Session ${dayEndSession.name} should end a day but does not\n");
      }

      // Only this many lunches per day. (Normally 1.)
      var targetLunches = targetLunchesPerDay;
      if (dayNumber == days.length && FINAL_HALF_DAY) targetLunches = 0;
      penalty.cultural += WRONG_NUM_LUNCHES *
          (targetLunches - day.where((s) => s.isLunch).length).abs();
      if (verbose && day.where((s) => s.isLunch).length != targetLunches)
        print(
            "Day $dayNumber should have $targetLunches lunches but have ${day.where((s) => s.isLunch).length}\n");

      // Keep the days not too long.
      penalty.awareness +=
          DAY_TOO_LONG * max(0, phenotype.getLength(day) - maxMinutesInDay);
      if (verbose && phenotype.getLength(day) > maxMinutesInDay)
        print(
            "Day $dayNumber should be $maxMinutesInDay minutes but is ${phenotype.getLength(day)}\n");
    }

    // Make sure coffee is available at regular intervals
    for (final noDrinkBlock
        in phenotype.getBlocksBetweenDrinks(ordered, sessions)) {
      if (noDrinkBlock.isEmpty) continue;

      penalty.hunger += TOO_THIRSTY *
          max(0, phenotype.getLength(noDrinkBlock) - maxMinutesWithoutDrink);
      if (verbose && phenotype.getLength(noDrinkBlock) > maxMinutesWithoutDrink)
        print(
            "Going without drink for ${phenotype.getLength(noDrinkBlock)} of $maxMinutesWithoutDrink minutes: ${noDrinkBlock.first.name}\n");
    }

    for (final noFoodBlock
        in phenotype.getBlocksBetweenLargeMeal(ordered, sessions)) {
      if (noFoodBlock.isEmpty) continue;

      // Penalize incorrect number of coffee breaks (should be 1)
      int nCoffeeBreaks = noFoodBlock.where((s) => s.isCoffee).length;
      penalty.cultural += (nCoffeeBreaks - 1).abs() * WRONG_NUM_COFFEE;
      if (verbose && nCoffeeBreaks != 1)
        print("Incorrect number of coffee breaks: $nCoffeeBreaks\n");

      // Penalize incorrect number of keynotes (should be 1)
      int nKeynotes = noFoodBlock.where((s) => s.isKeynote).length;
      penalty.cultural += (nKeynotes - 1).abs() * WRONG_NUM_KEYNOTE;
      if (verbose && nKeynotes != 1)
        print("Incorrect number of keynotes: $nKeynotes\n");

      // Keynotes should start days or be after lunch.
      for (final keynoteSession in noFoodBlock.where((s) => s.isKeynote)) {
        penalty.cultural +=
            noFoodBlock.indexOf(keynoteSession) * WRONG_TIME_KEYNOTE;
        if (verbose && noFoodBlock.indexOf(keynoteSession) > 0)
          print(
              "Keynote ${keynoteSession.name} has index ${noFoodBlock.indexOf(keynoteSession)}\n");
      }

      // Food should be available at regular intervals
      penalty.hunger += TOO_HUNGRY *
          max(0, phenotype.getLength(noFoodBlock) - maxMinutesWithoutLargeMeal);
      if (verbose &&
          phenotype.getLength(noFoodBlock) > maxMinutesWithoutLargeMeal)
        print(
            "Going without food for ${phenotype.getLength(noFoodBlock)} of $maxMinutesWithoutLargeMeal minutes\n");
    }

    void penalizeSeekAvoid(Session a, Session b) {
      // Avoid according to tags.
      penalty.repetitiveness +=
          FAIL_TO_AVOID * a.tags.where((tag) => b.avoid.contains(tag)).length;
      penalty.repetitiveness +=
          FAIL_TO_AVOID * b.tags.where((tag) => a.avoid.contains(tag)).length;
      // Seek according to tags.
      penalty.harmony -=
          GOOD_SEEK * a.tags.where((tag) => b.seek.contains(tag)).length;
      penalty.harmony -=
          GOOD_SEEK * b.tags.where((tag) => a.seek.contains(tag)).length;

      if (verbose && a.tags.where((tag) => b.avoid.contains(tag)).length > 0)
        print("Sessions ${a.name} and ${b.name} should not be adjacent\n");
      if (verbose && b.tags.where((tag) => a.avoid.contains(tag)).length > 0)
        print("Sessions ${a.name} and ${b.name} should not be adjacent\n");
    }

    for (final block in phenotype.getBlocks(ordered, sessions)) {
      // Avoid blocks that are too long.
      final blockLength = phenotype.getLength(block);
      penalty.awareness +=
          BLOCK_TOO_LONG * max(0, blockLength - maxMinutesWithoutBreak);
      if (verbose && blockLength > maxMinutesWithoutBreak)
        print("Block is $blockLength of $maxMinutesWithoutBreak minutes\n");
    }

    for (final tuple in phenotype.getTuples(ordered, sessions)) {
      final a = tuple[0];
      final b = tuple[1];

      penalizeSeekAvoid(a, b);
    }

    final baked = new BakedSchedule(ordered);

    // Penalize when last day is too long.
    final lastDay = baked.days[baked.days.length];
    penalty.constraints +=
        LAST_DAY_LONG * max(0.0, lastDay.end.difference(END_TIME).inMinutes);

    if (verbose && lastDay.end.difference(END_TIME).inMinutes > 0)
      print("Last day is too long\n");

    // Look at all last day sessions
    for (BakedSession bs in lastDay.list) {
      // Reward things that were correctly scheduled on the final day
      if (bs.session.isFinalDay) penalty.constraints -= GOOD_FINAL_DAY_SESSION;

      // Penalize things that weren't
      if (bs.session.notFinalDay) {
        penalty.constraints += BAD_FINAL_DAY_SESSION;
        if (verbose)
          print("${bs.session.name} should not be on the final day\n");
      }
    }

    // Lunch hour should start at a culturally appropriate time.
    for (final bakedDay in baked.days.values) {
      for (final baked in bakedDay.list) {
        if (!baked.session.isLunch) continue;
        final distance = _getDistanceFromLunchHour(baked.time);
        if (verbose && distance.inMinutes.abs() > 0)
          print(
              "Lunch at ${baked.time} is ${distance.inMinutes.abs()} minutes from ideal\n");
        penalty.cultural += BAD_LUNCH_TIME * distance.inMinutes.abs();
      }
    }

    final usedOrderIndexes = new Set<int>();
    for (final order in phenotype.genes) {
      if (usedOrderIndexes.contains(order)) {
        // One index used multiple times.
        penalty.dna += 0.1;
      }
      usedOrderIndexes.add(order);
    }

    return penalty;
  }

  static Duration _getDistanceFromLunchHour(DateTime time) {
    final lunchTimeMin =
        new DateTime.utc(time.year, time.month, time.day, _lunchHourMin);
    final lunchTimeMax =
        new DateTime.utc(time.year, time.month, time.day, _lunchHourMax);
    if (time.isAfter(lunchTimeMin) && time.isBefore(lunchTimeMax) ||
        time == lunchTimeMin ||
        time == lunchTimeMax) {
      // Inside range.
      return const Duration();
    }
    if (time.isBefore(lunchTimeMin)) {
      return lunchTimeMin.difference(time);
    }
    if (time.isAfter(lunchTimeMax)) {
      return lunchTimeMax.difference(time);
    }
    throw new StateError("time has undefined relationship to lunchTimeMin"
        " and lunchTimeMax");
  }
}

class ScheduleEvaluatorPenalty extends FitnessResult {
  /// Penalty for breaking expectations, like lunch at 12pm.
  double cultural = 0.0;

  /// Penalty for breaking constraints, like "end first day at 6pm".
  double constraints = 0.0;

  double hunger = 0.0;

  double repetitiveness = 0.0;

  /// Mostly bonus (negative values) for things like session of the same
  /// theme appearing after each other.
  double harmony = 0.0;

  /// Penalty for straining audience focus, like "not starting with exciting
  /// session after lunch".
  double awareness = 0.0;

  /// Penalty for ambivalence or other problems in the chromosome.
  double dna = 0.0;

  /// Used for debugging only.
  // ignore: unused_field
  double _cachedEvaluate;

  @override
  bool dominates(ScheduleEvaluatorPenalty other) {
    return cultural < other.cultural &&
        constraints < other.constraints &&
        hunger < other.hunger &&
        repetitiveness < other.repetitiveness &&
        harmony < other.harmony &&
        awareness < other.awareness &&
        dna < other.dna;
  }

  double evaluate() {
    double result = 0.0;
    result += cultural;
    result += constraints;
    result += hunger;
    result += repetitiveness;
    result += harmony;
    result += awareness;
    result += dna;
    _cachedEvaluate = result;
    return result;
  }
}

/// A function that takes a [schedule] and modifies the [penalty].
///
/// These are used for specific rules pertaining to only one conference but
/// not generally applicable, such as that a particular conference's first day
/// must end as close to 6pm as possible.
typedef void CustomEvaluator(
    BakedSchedule schedule, ScheduleEvaluatorPenalty penalty);
