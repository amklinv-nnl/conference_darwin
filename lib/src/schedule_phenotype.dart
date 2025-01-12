import 'dart:math';
import 'package:conference_darwin/src/baked_schedule.dart';
import 'package:conference_darwin/src/break_type.dart';
import 'package:conference_darwin/src/constants.dart';
import 'package:conference_darwin/src/evaluator.dart';
import 'package:conference_darwin/src/session.dart';
import 'package:darwin/darwin.dart';

class Schedule extends Phenotype<int, ScheduleEvaluatorPenalty> {
  final int sessionCount;

  final int nDayBreaks;

  int maxExtraLunchCount;

  int maxCoffeeBreaksCount;

  final int orderRange;

  /// Order above this value will not appear in the program.
  final int orderRangeCutOff;

  int maxShortBreaksCount;

  int _geneCount;

  final _random = new Random();

  Schedule(List<Session> sessions, int dayCount)
      : sessionCount = sessions.length,
        nDayBreaks = dayCount - 1,
        maxExtraLunchCount = dayCount - sessions.where((s) => s.isLunch).length,
        maxCoffeeBreaksCount = 2 * dayCount,
        orderRange = sessions.length * 6,
        orderRangeCutOff = sessions.length * 5 {
    if (FINAL_HALF_DAY) {
      maxExtraLunchCount = max(0, maxExtraLunchCount - 1);
      maxCoffeeBreaksCount -= 1;
    }

    maxShortBreaksCount =
        sessionCount - nDayBreaks - maxExtraLunchCount - maxCoffeeBreaksCount;

    _geneCount = sessionCount +
        nDayBreaks +
        maxExtraLunchCount +
        maxShortBreaksCount +
        maxCoffeeBreaksCount;
  }

  factory Schedule.random(List<Session> sessions, int dayCount) {
    final schedule = new Schedule(sessions, dayCount);
    schedule.genes = new List<int>(schedule._geneCount);
    for (int i = 0; i < schedule._geneCount; i++) {
      schedule.genes[i] = schedule._random.nextInt(schedule.orderRange);
    }
    return schedule;
  }

  @override
  int get hashCode {
    return genes.hashCode;
  }

  bool operator ==(other) {
    if (other is! Schedule) return false;
    return hashCode == other.hashCode;
  }

  @override
  num computeHammingDistance(Schedule other) {
    int aLast = -1;
    int bLast = -1;
    int differences = 0;
    bool aFound;
    bool bFound;
    do {
      aFound = false;
      bFound = false;
      int aBestCandidateValue = orderRange * 1000;
      int bBestCandidateValue = orderRange * 1000;
      int aBestCandidateIndex;
      int bBestCandidateIndex;
      // go through all genes and find the current lowest one
      for (int i = 0; i < _geneCount; i++) {
        final aCurrent = genes[i];
        if (aLast < aCurrent && aCurrent < aBestCandidateValue) {
          aBestCandidateValue = aCurrent;
          aBestCandidateIndex = i;
          aFound = true;
        }
        final bCurrent = other.genes[i];
        if (bLast < bCurrent && bCurrent < bBestCandidateValue) {
          bBestCandidateValue = bCurrent;
          bBestCandidateIndex = i;
          bFound = true;
        }
      }
      if (aFound || bFound) {
        if (aBestCandidateIndex != bBestCandidateIndex) {
          // Add a difference when the value was on a different index.
          differences += 1;
        }
        if (aFound) {
          aLast = aBestCandidateValue;
        }
        if (bFound) {
          bLast = bBestCandidateValue;
        }
      }
    } while (aFound || bFound);

    assert(differences <= _geneCount);

    return differences / _geneCount;
  }

  String generateSchedule(List<Session> sessions) {
    final ordered = getOrdered(sessions);
    final baked = new BakedSchedule(ordered);
    final buf = new StringBuffer();

    // Print the first day
    buf.write("\t16:45\tStudent Days Orientation\t60\n");
    buf.write("\t17:45\tWelcome Reception\t120\n");
    buf.write("\t19:45\t");
    buf.write(printBreakType(BreakType.day));
    buf.write("\t0\n\n");

    for (final slot in baked.list) {
      //if (slot.session.isShortBreak) continue;

      buf.write("\t");
      final hour = slot.time.hour;
      final minute = slot.time.minute.toString().padLeft(2, '0');
      buf.write("$hour:$minute");
      buf.write("\t");
      buf.write(slot.session.name);
      buf.write("\t");
      buf.write(slot.session.length);
      buf.writeln();

      if (slot.session.isDayBreak) buf.writeln();
    }
    return buf.toString();
  }

  Iterable<List<Session>> getBlocks(
      List<Session> ordered, List<Session> sessions) sync* {
    var block = <Session>[];
    for (final session in ordered) {
      if (session.isBreak || session.isPoster) {
        yield block;
        block = <Session>[];
        continue;
      }
      block.add(session);
    }
    yield block;
  }

  Iterable<List<Session>> getBlocksBetweenLargeMeal(
      List<Session> ordered, List<Session> sessions) sync* {
    var block = <Session>[];
    for (final session in ordered) {
      if (session.isLunch || session.isDayBreak) {
        yield block;
        block = <Session>[];
        continue;
      }
      block.add(session);
    }
    yield block;
  }

  Iterable<List<Session>> getBlocksBetweenDrinks(
      List<Session> ordered, List<Session> sessions) sync* {
    var block = <Session>[];
    for (final session in ordered) {
      if (session.isLunch ||
          session.isDayBreak ||
          session.isCoffee ||
          session.isPoster) {
        yield block;
        block = <Session>[];
        continue;
      }
      block.add(session);
    }
    yield block;
  }

  Iterable<List<Session>> getDays(
      List<Session> ordered, List<Session> sessions) sync* {
    var day = <Session>[];
    for (final session in ordered) {
      if (session.isDayBreak) {
        yield day;
        day = <Session>[];
        continue;
      }
      day.add(session);
    }
    yield day;
  }

  int getLength(Iterable<Session> sessions) {
    int length = 0;
    for (final session in sessions) {
      if (session.isPoster)
        length += session.length ~/ 2.0;
      else
        length += session.length;
    }
    return length;
  }

  List<Session> getOrdered(List<Session> original) {
    int geneIndex = 0;
    // Maps sessions to their order.
    final allSessions = new Map<Session, int>();
    for (int i = 0; i < original.length; i++) {
      allSessions[original[i]] = genes[geneIndex];
      geneIndex += 1;
    }
    for (int i = 0; i < maxShortBreaksCount; i++) {
      final shortBreak = new Session.defaultShortBreak();
      allSessions[shortBreak] = genes[geneIndex];
      geneIndex += 1;
    }
    for (int i = 0; i < maxCoffeeBreaksCount; i++) {
      final coffeeBreak = new Session.defaultCoffeeBreak();
      allSessions[coffeeBreak] = genes[geneIndex];
      geneIndex += 1;
    }
    for (int i = 0; i < maxExtraLunchCount; i++) {
      final lunch = new Session.defaultLunch();
      allSessions[lunch] = genes[geneIndex];
      geneIndex += 1;
    }
    for (int i = 0; i < nDayBreaks; i++) {
      final dayBreak = new Session.defaultDayBreak();
      allSessions[dayBreak] = genes[geneIndex];
      geneIndex += 1;
    }
    final ordered = new List<Session>.from(
        allSessions.keys.where((key) => allSessions[key] < orderRangeCutOff));
    ordered.sort((a, b) => allSessions[a].compareTo(allSessions[b]));
    return ordered;
  }

  /// Returns an iterable of doubles - sessions that are next to each
  /// other with no break between.
  Iterable<List<Session>> getTuples(
      List<Session> ordered, List<Session> sessions) sync* {
    for (int i = 1; i < ordered.length; i++) {
      final a = ordered[i - 1];
      final b = ordered[i];
      yield [a, b];
    }
  }

  @override
  int mutateGene(int gene, num strength) {
    int maxDiff = (orderRange * strength).round();
    int diff = _random.nextInt(maxDiff) - (orderRange ~/ 2);
    return (gene + diff) % orderRange;
  }
}
