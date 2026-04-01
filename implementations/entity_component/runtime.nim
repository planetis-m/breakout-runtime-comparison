import std/[math, random]
import ../../bench_sizes
import ../../shared/[headless_raylib, vmath]
# ---- entity-component runtime ----

type
  Input* = enum
    Right, Left

  CollisionFlag* = enum
    Hit

  TransformFlag* = enum
    Dirty, Fresh, HasPrevious

  EntityKind* = enum
    CameraKind,
    PaddleKind,
    BallKind,
    BrickKind,
    ParticleKind,
    TrailKind

  Collision* = object
    flags*: set[CollisionFlag]
    hit*: Vec2

  TransformComponent* = object
    world*: Mat2d
    translation*: Vec2
    rotation*: Rad
    scale*: Vec2
    flags*: set[TransformFlag]

  CollideComponent* = ref object
    size*: Vec2
    min*, max*: Point2
    center*: Point2
    collision*: Collision

  Draw2dComponent* = ref object
    width*, height*: int32
    color*: array[4, uint8]

  FadeComponent* = ref object
    step*: float32

  MoveComponent* = ref object
    direction*: Vec2
    speed*: float32

  PreviousComponent* = object
    position*: Point2
    rotation*: Rad
    scale*: Vec2

  ShakeComponent* = ref object
    duration*: float32
    strength*: float32

  Entity* = ref object
    alive*: bool
    kind*: EntityKind
    parent*: Entity
    children*: seq[Entity]

    transform*: TransformComponent
    previous*: PreviousComponent

    collide*: CollideComponent

    draw2d*: Draw2dComponent

    fade*: FadeComponent

    move*: MoveComponent

    shake*: ShakeComponent

  Game* = object
    camera*: Entity
    paddle*: Entity
    entities*: seq[Entity]

    inputState*: array[Input, bool]
    clearColor*: array[4, uint8]

    isRunning*: bool
    windowWidth*, windowHeight*: int32
    tickId*: int

    raylib*: RaylibContext

func intersects*[K: enum](a, b: set[K]): bool {.inline.} =
  (a * b) != {}

proc newEntity*(game: var Game; kind: EntityKind; parent: Entity = nil): Entity =
  result = Entity(
    alive: true,
    kind: kind,
    parent: parent,
    children: @[],
    transform: TransformComponent(
      world: mat2d(),
      translation: vec2(0, 0),
      rotation: 0.Rad,
      scale: vec2(1, 1),
      flags: {Dirty, Fresh}
    ),
    previous: PreviousComponent(
      position: point2(0, 0),
      rotation: 0.Rad,
      scale: vec2(1, 1)
    )
  )
  game.entities.add(result)
  if parent != nil:
    parent.children.add(result)

proc markDirty*(entity: Entity) =
  if entity != nil:
    entity.transform.flags.incl(Dirty)

proc createBall*(game: var Game; x, y: float32) =
  let angle = PI.float32 + rand(1.0'f32) * PI.float32
  let entity = game.newEntity(BallKind, game.camera)
  entity.transform.translation = vec2(x, y)
  entity.collide = CollideComponent(
    size: vec2(20, 20),
    min: point2(0, 0),
    max: point2(0, 0),
    center: point2(0, 0),
    collision: Collision(flags: {}, hit: vec2(0, 0))
  )
  entity.draw2d = Draw2dComponent(width: 20, height: 20, color: [0'u8, 255, 0, 255])
  entity.move = MoveComponent(
    direction: Vec2(x: cos(angle), y: sin(angle)),
    speed: 14
  )

proc createBrick*(game: var Game; x, y: float32; width, height: int32) =
  let entity = game.newEntity(BrickKind, game.camera)
  entity.transform.translation = vec2(x, y)
  entity.collide = CollideComponent(
    size: vec2(width.float32, height.float32),
    min: point2(0, 0),
    max: point2(0, 0),
    center: point2(0, 0),
    collision: Collision(flags: {}, hit: vec2(0, 0))
  )
  entity.draw2d = Draw2dComponent(width: width, height: height, color: [255'u8, 255, 0, 255])
  entity.fade = FadeComponent(step: 0)

proc createExplosion*(game: var Game; x, y: float32) =
  let explosions = 32
  let step = TAU / explosions.float
  let fadeStep = 0.05
  for i in 0..<explosions:
    let entity = game.newEntity(ParticleKind, game.camera)
    entity.transform.translation = vec2(x, y)
    entity.draw2d = Draw2dComponent(width: 20, height: 20, color: [255'u8, 255, 255, 255])
    entity.fade = FadeComponent(step: fadeStep)
    entity.move = MoveComponent(
      direction: Vec2(x: sin(step * i.float32), y: cos(step * i.float32)),
      speed: 20
    )

proc createTrail*(game: var Game; x, y: float32) =
  let entity = game.newEntity(TrailKind, game.camera)
  entity.transform.translation = vec2(x, y)
  entity.draw2d = Draw2dComponent(width: 20, height: 20, color: [0'u8, 255, 0, 255])
  entity.fade = FadeComponent(step: 0.05)

proc createPaddle*(game: var Game; x, y: float32) =
  let entity = game.newEntity(PaddleKind, game.camera)
  entity.transform.translation = vec2(x, y)
  entity.collide = CollideComponent(
    size: vec2(100, 20),
    min: point2(0, 0),
    max: point2(0, 0),
    center: point2(0, 0),
    collision: Collision(flags: {}, hit: vec2(0, 0))
  )
  entity.draw2d = Draw2dComponent(width: 100, height: 20, color: [255'u8, 0, 0, 255])
  entity.move = MoveComponent(direction: vec2(0, 0), speed: 20)
  game.paddle = entity

proc createScene*(game: var Game; scale: BenchScale) =
  let columnCount = scale.columns
  let rowCount = scale.rows
  let brickWidth = 50
  let brickHeight = 15
  let margin = 5

  let gridWidth = brickWidth * columnCount + margin * (columnCount - 1)
  let startingX = (game.windowWidth - gridWidth) div 2
  let startingY = 50

  game.camera = game.newEntity(CameraKind)
  game.camera.shake = ShakeComponent(duration: 0, strength: 10)

  game.createPaddle(float32(game.windowWidth / 2), float32(game.windowHeight - 30))
  game.createBall(float32(game.windowWidth / 2), float32(game.windowHeight - 60))

  for row in 0..<rowCount:
    let y = startingY + row * (brickHeight + margin) + brickHeight div 2
    for col in 0..<columnCount:
      let x = startingX + col * (brickWidth + margin) + brickWidth div 2
      game.createBrick(x.float32, y.float32, brickWidth.int32, brickHeight.int32)

proc sysControlPaddle*(game: var Game) =
  if game.paddle == nil or not game.paddle.alive:
    return
  game.paddle.move.direction.x = 0
  if game.inputState[Left]:
    game.paddle.move.direction.x -= 1
  if game.inputState[Right]:
    game.paddle.move.direction.x += 1

proc sysControlBall*(game: var Game) =
  let entityCount = game.entities.len
  for i in 0..<entityCount:
    let ball = game.entities[i]
    if not ball.alive or ball.kind != BallKind:
      continue

    template collide: untyped = ball.collide
    template move: untyped = ball.move
    template transform: untyped = ball.transform

    if collide.min.x < 0:
      transform.translation.x = collide.size.x / 2
      move.direction.x *= -1
    if collide.max.x > game.windowWidth.float32:
      transform.translation.x = game.windowWidth.float32 - collide.size.x / 2
      move.direction.x *= -1
    if collide.min.y < 0:
      transform.translation.y = collide.size.y / 2
      move.direction.y *= -1
    if collide.max.y > game.windowHeight.float32:
      transform.translation.y = game.windowHeight.float32 - collide.size.y / 2
      move.direction.y *= -1

    if Hit in collide.collision.flags:
      game.camera.shake.duration = 0.1
      if collide.collision.hit.x != 0:
        transform.translation.x += collide.collision.hit.x
        move.direction.x *= -1
      if collide.collision.hit.y != 0:
        transform.translation.y += collide.collision.hit.y
        move.direction.y *= -1
      game.createExplosion(transform.translation.x, transform.translation.y)

    ball.markDirty()
    game.createTrail(transform.translation.x, transform.translation.y)

proc sysControlBrick*(game: var Game) =
  let entityCount = game.entities.len
  for i in 0..<entityCount:
    let brick = game.entities[i]
    if brick.alive and brick.kind == BrickKind and Hit in brick.collide.collision.flags:
      brick.fade.step = 0.05
      if rand(1.0) > 0.98:
        game.createBall(float32(game.windowWidth / 2), float32(game.windowHeight / 2))

proc sysShake*(game: var Game) =
  if game.camera == nil or game.camera.shake == nil:
    return

  template transform: untyped = game.camera.transform
  template shake: untyped = game.camera.shake

  if shake.duration > 0:
    shake.duration -= 0.01
    transform.translation.x = shake.strength - rand(shake.strength * 2)
    transform.translation.y = shake.strength - rand(shake.strength * 2)
    game.clearColor[0] = rand(255).uint8
    game.clearColor[1] = rand(255).uint8
    game.clearColor[2] = rand(255).uint8
    game.camera.markDirty()

    if shake.duration <= 0:
      shake.duration = 0
      transform.translation = vec2(0, 0)
      game.clearColor[0] = 0
      game.clearColor[1] = 0
      game.clearColor[2] = 0
      game.camera.markDirty()

proc sysFade*(game: var Game) =
  for entity in game.entities.mitems:
    if not entity.alive or entity.fade == nil or entity.draw2d == nil:
      continue
    if entity.draw2d.color[3] > 0:
      let step = 255 * entity.fade.step
      entity.draw2d.color[3] = entity.draw2d.color[3] - step.uint8
      entity.transform.scale.x -= entity.fade.step
      entity.transform.scale.y -= entity.fade.step
      entity.markDirty()
      if entity.transform.scale.x <= 0:
        entity.alive = false

proc detachFromParent(entity: Entity) =
  if entity.parent == nil:
    return
  for i in countdown(entity.parent.children.high, 0):
    if entity.parent.children[i] == entity:
      entity.parent.children.del(i)
      break
  entity.parent = nil

proc cleanupDead*(game: var Game) =
  for i in countdown(game.entities.high, 0):
    let entity = game.entities[i]
    if entity.alive:
      continue
    entity.detachFromParent()
    for child in entity.children.items:
      child.parent = nil
    entity.children.setLen(0)
    if game.paddle == entity:
      game.paddle = nil
    if game.camera == entity:
      game.camera = nil
    game.entities.del(i)

proc sysMove*(game: var Game) =
  for entity in game.entities.items:
    if not entity.alive or entity.move == nil:
      continue
    if entity.kind notin {PaddleKind, BallKind, ParticleKind}:
      continue
    let move = entity.move
    if move.direction.x != 0 or move.direction.y != 0:
      entity.transform.translation.x += move.direction.x * move.speed
      entity.transform.translation.y += move.direction.y * move.speed
      entity.markDirty()

proc updateTransformWorld(entity: Entity) =
  template transform: untyped = entity.transform
  template previous: untyped = entity.previous

  if Fresh in transform.flags:
    transform.flags.excl(Fresh)
  else:
    previous.position = transform.world.origin
    previous.rotation = transform.world.rotation
    previous.scale = transform.world.scale
    transform.flags.incl(HasPrevious)
    transform.flags.excl(Dirty)

  let local = compose(transform.scale, transform.rotation, transform.translation)
  if entity.parent != nil:
    transform.world = entity.parent.transform.world * local
  else:
    transform.world = local

proc sysTransform2d*(game: var Game) =
  if game.camera == nil:
    return
  var stack: seq[Entity] = @[]
  var current = game.camera

  while current != nil:
    for i in countdown(current.children.high, 0):
      stack.add(current.children[i])

    if current.alive and current.transform.flags.intersects({Dirty, Fresh}):
      current.updateTransformWorld()

    if stack.len > 0:
      current = stack.pop()
    else:
      current = nil

proc computeAabb(transform: TransformComponent; collide: CollideComponent) =
  collide.center = transform.world.origin
  collide.min = collide.center - collide.size / 2
  collide.max = collide.center + collide.size / 2

proc intersectAabb(a, b: CollideComponent): bool =
  a.min.x < b.max.x and a.min.y < b.max.y and
    a.max.x > b.min.x and a.max.y > b.min.y

proc penetrateAabb(a, b: CollideComponent): Vec2 =
  let distanceX = a.center.x - b.center.x
  let penetrationX = a.size.x / 2 + b.size.x / 2 - abs(distanceX)
  let distanceY = a.center.y - b.center.y
  let penetrationY = a.size.y / 2 + b.size.y / 2 - abs(distanceY)

  if penetrationX < penetrationY:
    result = vec2(penetrationX * sgn(distanceX).float32, 0)
  else:
    result = vec2(0, penetrationY * sgn(distanceY).float32)

proc prepareCollider(entity: Entity) =
  entity.collide.collision = Collision(flags: {}, hit: vec2(0, 0))
  computeAabb(entity.transform, entity.collide)

proc updateCollision(a, b: Entity) =
  if intersectAabb(a.collide, b.collide):
    let hit = penetrateAabb(a.collide, b.collide)
    a.collide.collision = Collision(flags: {Hit}, hit: hit)
    b.collide.collision = Collision(flags: {Hit}, hit: -hit)

proc sysCollide*(game: var Game) =
  if game.paddle != nil and game.paddle.alive:
    game.paddle.prepareCollider()

  for entity in game.entities.items:
    if entity.alive and entity.collide != nil and entity.kind in {BallKind, BrickKind}:
      entity.prepareCollider()

  for ball in game.entities.items:
    if not ball.alive or ball.kind != BallKind:
      continue
    if game.paddle != nil and game.paddle.alive:
      updateCollision(ball, game.paddle)
    for brick in game.entities.items:
      if brick.alive and brick.kind == BrickKind:
        updateCollision(ball, brick)

const Tolerance = 0.75'f32

proc drawTransform(entity: Entity; intrpl: float32) =
  if HasPrevious notin entity.transform.flags or entity.draw2d == nil:
    return

  let position = lerp(entity.previous.position, entity.transform.world.origin, intrpl)
  let scale = lerp(entity.previous.scale, entity.transform.world.scale, intrpl)
  let width = int32(entity.draw2d.width.float32 * scale.x)
  let height = int32(entity.draw2d.height.float32 * scale.y)

  var x = position.x.int32
  var y = position.y.int32
  if abs(position.x - x.float32) > Tolerance:
    x = ceil(position.x).int32
  if abs(position.y - y.float32) > Tolerance:
    y = ceil(position.y).int32

  drawRectangle(
    x - int32(width / 2),
    y - int32(height / 2),
    width,
    height,
    entity.draw2d.color
  )

proc sysDraw2d*(game: var Game; intrpl: float32) =
  clearBackground(game.clearColor)
  for entity in game.entities.items:
    if entity.alive and entity.draw2d != nil:
      entity.drawTransform(intrpl)

proc handleEvents*(game: var Game) =
  pollInput()
  if windowShouldClose() or keyPressed(KEY_ESCAPE):
    game.isRunning = false
  game.inputState[Left] = keyDown(KEY_LEFT) or keyDown(KEY_A)
  game.inputState[Right] = keyDown(KEY_RIGHT) or keyDown(KEY_D)
