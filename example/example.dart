import 'dart:io';
import 'package:conference_darwin/conference_darwin.dart';
import 'package:darwin/darwin.dart';
import 'package:yaml/yaml.dart';

main() async {
  File file = new File('events.yaml');
  String yamlString = file.readAsStringSync();
  Map yaml = loadYaml(yamlString);

  var sessions = <Session>[];

  yaml.forEach((key, value) {
    String type;
    if (value.containsKey("type"))
      type = value["type"];
    else
      type = "unknown";

    // Set default duration
    int duration;
    if (value.containsKey("duration"))
      duration = value["duration"];
    else if (DURATIONS.containsKey(type))
      duration = DURATIONS[type];
    else
      duration = DURATIONS["default"];

    // Set default tags
    List<String> tags;
    if (value.containsKey("tags"))
      tags = value["tags"].toList().cast<String>();
    else if (TAGS.containsKey(type))
      tags = TAGS[type];
    else
      tags = TAGS["default"];

    // Set default seek
    List<String> seek;
    if (value.containsKey("seek"))
      seek = value["seek"].toList().cast<String>();
    else if (SEEK.containsKey(type))
      seek = SEEK[type];
    else
      seek = SEEK["default"];

    // Set default avoid
    List<String> avoid;
    if (value.containsKey("avoid"))
      avoid = value["avoid"].toList().cast<String>();
    else if (AVOID.containsKey(type))
      avoid = AVOID[type];
    else
      avoid = AVOID["default"];

    sessions
        .add(new Session(key, duration, tags: tags, seek: seek, avoid: avoid));
  });

  final firstGeneration =
      new Generation<Schedule, int, ScheduleEvaluatorPenalty>()
        ..members.addAll(new List.generate(
            200, (_) => new Schedule.random(sessions, NUM_DAYS)));

  final evaluator = new ScheduleEvaluator(sessions);

  final breeder =
      new GenerationBreeder<Schedule, int, ScheduleEvaluatorPenalty>(
          () => new Schedule(sessions, NUM_DAYS))
        ..fitnessSharingRadius = 0.5
        ..elitismCount = 1;

  final algo = new GeneticAlgorithm<Schedule, int, ScheduleEvaluatorPenalty>(
      firstGeneration, evaluator, breeder,
      printf: (_) {})
    ..maxExperiments = 100000
    ..thresholdResult = new ScheduleEvaluatorPenalty();

  algo.onGenerationEvaluated.listen((gen) {
    if (algo.currentGeneration == 0) return;
    if (algo.currentGeneration % 100 != 0) return;

    printResults(gen, sessions, evaluator);
  });

  await algo.runUntilDone();
  printResults(algo.generations.last, sessions, evaluator);
}

void printResults(Generation<Schedule, int, ScheduleEvaluatorPenalty> gen,
    List<Session> sessions, ScheduleEvaluator evaluator) {
  final lastGeneration = new List<Schedule>.from(gen.members);
  lastGeneration.sort();
  for (int i = 0; i < 1; i++) {
    final specimen = lastGeneration[i];
    evaluator.internalEvaluate(specimen, verbose: true);
    print("======= Winner $i ("
        "pareto rank ${specimen.result.paretoRank} "
        "fitness ${specimen.result.evaluate().toStringAsFixed(2)} "
        "shared ${specimen.resultWithFitnessSharingApplied.toStringAsFixed(2)} "
        ") ====");
    print("${specimen.genesAsString}");
    print(specimen.generateSchedule(sessions));
  }
}
