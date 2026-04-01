import std/[monotimes, random, strutils]

when not compileOption("threads"):
  {.error: "breakout-runtime-comparison must be built with --threads:on".}

const
  WindowWidth* = 740'i32
  WindowHeight* = 555'i32
  TickCount* = 2_000
  Repetitions* = 5

type
  Timings* = object
    controlBall*, controlBrick*, controlPaddle*: int64
    shake*, fade*, cleanupDead*, move*, transform2d*, collide*: int64

  Snapshot* = object
    live*: int
    total*: int
    max*: int
    paddle*, ball*, brick*, particle*, trail*, dead*: int
    extra*: string

template timeInto*(slot: untyped; body: untyped) =
  block:
    let start = getMonoTime().ticks
    body
    slot += getMonoTime().ticks - start

proc benchmarkMain*[G](
  label: string,
  initBenchGame: proc (): G,
  createScene: proc (game: var G),
  applyInput: proc (game: var G; tick: int),
  update: proc (game: var G; timings: var Timings),
  snapshot: proc (game: G): Snapshot
) =
  var totalNs = 0'i64
  var totalTimings = Timings()
  var lastSnapshot = Snapshot()

  for rep in 0..<Repetitions:
    randomize(12345)
    var game = initBenchGame()
    createScene(game)
    var timings = Timings()
    var peak = snapshot(game)
    let start = getMonoTime().ticks

    for tick in 0..<TickCount:
      applyInput(game, tick)
      update(game, timings)
      let current = snapshot(game)
      if current.total > peak.max:
        peak.max = current.total

    let elapsedNs = getMonoTime().ticks - start
    var finalSnapshot = snapshot(game)
    finalSnapshot.max = peak.max
    lastSnapshot = finalSnapshot
    totalNs += elapsedNs
    totalTimings.controlBall += timings.controlBall
    totalTimings.controlBrick += timings.controlBrick
    totalTimings.controlPaddle += timings.controlPaddle
    totalTimings.shake += timings.shake
    totalTimings.fade += timings.fade
    totalTimings.cleanupDead += timings.cleanupDead
    totalTimings.move += timings.move
    totalTimings.transform2d += timings.transform2d
    totalTimings.collide += timings.collide
    echo label, " rep ", rep + 1, ": ",
      formatFloat(elapsedNs.float64 / 1_000_000.0, ffDecimal, 3), "ms"

  let avgNs = totalNs div Repetitions
  echo label, " avg: ",
    formatFloat(avgNs.float64 / 1_000_000.0, ffDecimal, 3),
    "ms total, ",
    formatFloat(avgNs.float64 / TickCount.float64, ffDecimal, 3),
    "ns/tick"
  echo label, " entities: live=", lastSnapshot.live, " total=",
    lastSnapshot.total, " max=", lastSnapshot.max
  echo label, " kinds: paddle=", lastSnapshot.paddle, " ball=",
    lastSnapshot.ball, " brick=", lastSnapshot.brick, " particle=",
    lastSnapshot.particle, " trail=", lastSnapshot.trail, " dead=",
    lastSnapshot.dead
  if lastSnapshot.extra.len > 0:
    echo label, " extra: ", lastSnapshot.extra
  echo label, " sys controlBall=",
    formatFloat((totalTimings.controlBall div Repetitions).float64 / 1_000_000.0, ffDecimal, 3), "ms"
  echo label, " sys controlBrick=",
    formatFloat((totalTimings.controlBrick div Repetitions).float64 / 1_000_000.0, ffDecimal, 3), "ms"
  echo label, " sys controlPaddle=",
    formatFloat((totalTimings.controlPaddle div Repetitions).float64 / 1_000_000.0, ffDecimal, 3), "ms"
  echo label, " sys shake=",
    formatFloat((totalTimings.shake div Repetitions).float64 / 1_000_000.0, ffDecimal, 3), "ms"
  echo label, " sys fade=",
    formatFloat((totalTimings.fade div Repetitions).float64 / 1_000_000.0, ffDecimal, 3), "ms"
  echo label, " sys cleanupDead=",
    formatFloat((totalTimings.cleanupDead div Repetitions).float64 / 1_000_000.0, ffDecimal, 3), "ms"
  echo label, " sys move=",
    formatFloat((totalTimings.move div Repetitions).float64 / 1_000_000.0, ffDecimal, 3), "ms"
  echo label, " sys transform2d=",
    formatFloat((totalTimings.transform2d div Repetitions).float64 / 1_000_000.0, ffDecimal, 3), "ms"
  echo label, " sys collide=",
    formatFloat((totalTimings.collide div Repetitions).float64 / 1_000_000.0, ffDecimal, 3), "ms"
