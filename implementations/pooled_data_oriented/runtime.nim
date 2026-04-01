import std/[math, random]
import ../../shared/[headless_raylib, vmath]
# ---- pools ----
type
  Pool*[T, I] = object
    items: seq[T]
    freeList: seq[int32]

proc alloc*[T, I](pool: var Pool[T, I]; value: sink T): I {.inline.} =
  if pool.freeList.len > 0:
    result = I(pool.freeList.pop())
    pool.items[result.int] = value
  else:
    result = I(pool.items.len.int32)
    pool.items.add(value)

proc free*[T, I](pool: var Pool[T, I]; idx: I) {.inline.} =
  pool.items[idx.int] = default(T)
  pool.freeList.add(idx.int32)

proc `[]`*[T, I](pool: Pool[T, I]; idx: I): lent T {.inline.} =
  pool.items[idx.int]

proc `[]`*[T, I](pool: var Pool[T, I]; idx: I): var T {.inline.} =
  pool.items[idx.int]

# ---- gametypes ----

type
  Input* = enum
    Right, Left

  CollisionFlag* = enum
    Hit

  TransformFlag* = enum
    Dirty, Fresh, HasPrevious

  ActorKind* = enum
    DeadKind,
    PaddleKind,
    BallKind,
    BrickKind,
    ParticleKind,
    TrailKind

  ActorIdx* = distinct int32
  TransformIdx* = distinct int32
  HierarchyIdx* = distinct int32
  PreviousIdx* = distinct int32
  CollideIdx* = distinct int32
  Draw2dIdx* = distinct int32
  FadeIdx* = distinct int32
  MoveIdx* = distinct int32

  Collision* = object
    flags*: set[CollisionFlag]
    hit*: Vec2

  Hierarchy* = object
    head*: HierarchyIdx
    prev*: HierarchyIdx
    next*: HierarchyIdx
    parent*: HierarchyIdx

  Collide* = object
    size*: Vec2
    min*, max*: Point2
    center*: Point2
    collision*: Collision

  Draw2d* = object
    width*, height*: int32
    color*: array[4, uint8]

  Fade* = object
    step*: float32

  Move* = object
    direction*: Vec2
    speed*: float32

  Previous* = object
    position*: Point2
    rotation*: Rad
    scale*: Vec2

  Transform2d* = object
    world*: Mat2d
    translation*: Vec2
    rotation*: Rad
    scale*: Vec2
    flags*: set[TransformFlag]

  Shake* = object
    duration*: float32
    strength*: float32

  Camera* = object
    transform*: TransformIdx
    shake*: Shake

  Actor* = object
    kind*: ActorKind
    transform*: TransformIdx
    collide*: CollideIdx
    draw2d*: Draw2dIdx
    fade*: FadeIdx
    move*: MoveIdx

  Game* = object
    camera*: Camera
    paddle*: ActorIdx
    actors*: seq[Actor]

    transforms*: Pool[Transform2d, TransformIdx]
    hierarchies*: Pool[Hierarchy, HierarchyIdx]
    previous*: Pool[Previous, PreviousIdx]
    colliders*: Pool[Collide, CollideIdx]
    drawables*: Pool[Draw2d, Draw2dIdx]
    fades*: Pool[Fade, FadeIdx]
    moves*: Pool[Move, MoveIdx]

    inputState*: array[Input, bool]
    clearColor*: array[4, uint8]

    isRunning*: bool
    windowWidth*, windowHeight*: int32
    tickId*: int

    raylib*: RaylibContext

const
  NoActorIdx* = ActorIdx(-1'i32)
  NoTransformIdx* = TransformIdx(-1'i32)
  NoHierarchyIdx* = HierarchyIdx(-1'i32)
  NoPreviousIdx* = PreviousIdx(-1'i32)
  NoCollideIdx* = CollideIdx(-1'i32)
  NoDraw2dIdx* = Draw2dIdx(-1'i32)
  NoFadeIdx* = FadeIdx(-1'i32)
  NoMoveIdx* = MoveIdx(-1'i32)

proc `==`*(a, b: ActorIdx): bool {.borrow.}
proc `==`*(a, b: TransformIdx): bool {.borrow.}
proc `==`*(a, b: HierarchyIdx): bool {.borrow.}
proc `==`*(a, b: PreviousIdx): bool {.borrow.}
proc `==`*(a, b: CollideIdx): bool {.borrow.}
proc `==`*(a, b: Draw2dIdx): bool {.borrow.}
proc `==`*(a, b: FadeIdx): bool {.borrow.}
proc `==`*(a, b: MoveIdx): bool {.borrow.}

func containsAll*[K: enum](mask, required: set[K]): bool {.inline.} =
  required <= mask

func intersects*[K: enum](a, b: set[K]): bool {.inline.} =
  (a * b) != {}

func hierarchyIdx*(idx: TransformIdx): HierarchyIdx {.inline.} =
  HierarchyIdx(idx.int32)

func previousIdx*(idx: TransformIdx): PreviousIdx {.inline.} =
  PreviousIdx(idx.int32)

func transformIdx*(idx: HierarchyIdx): TransformIdx {.inline.} =
  TransformIdx(idx.int32)

proc parent*(game: Game; idx: TransformIdx): TransformIdx =
  let parentHierarchyIdx = game.hierarchies[idx.hierarchyIdx].parent
  if parentHierarchyIdx == NoHierarchyIdx:
    result = NoTransformIdx
  else:
    result = parentHierarchyIdx.transformIdx

proc firstChild*(game: Game; idx: TransformIdx): TransformIdx =
  let childHierarchyIdx = game.hierarchies[idx.hierarchyIdx].head
  if childHierarchyIdx == NoHierarchyIdx:
    result = NoTransformIdx
  else:
    result = childHierarchyIdx.transformIdx

proc nextSibling*(game: Game; idx: TransformIdx): TransformIdx =
  let siblingHierarchyIdx = game.hierarchies[idx.hierarchyIdx].next
  if siblingHierarchyIdx == NoHierarchyIdx:
    result = NoTransformIdx
  else:
    result = siblingHierarchyIdx.transformIdx

proc prependChild(game: var Game; parent, child: TransformIdx) =
  let childHierarchyIdx = child.hierarchyIdx
  let parentHierarchyIdx = parent.hierarchyIdx
  template hierarchy: untyped = game.hierarchies[childHierarchyIdx]
  template parentHierarchy: untyped = game.hierarchies[parentHierarchyIdx]

  hierarchy.parent = parentHierarchyIdx
  hierarchy.prev = NoHierarchyIdx
  hierarchy.next = parentHierarchy.head
  if parentHierarchy.head != NoHierarchyIdx:
    game.hierarchies[parentHierarchy.head].prev = childHierarchyIdx
  parentHierarchy.head = childHierarchyIdx

proc removeNode(game: var Game; node: TransformIdx) =
  let idx = node.hierarchyIdx
  template hierarchy: untyped = game.hierarchies[idx]

  let parent = hierarchy.parent
  let prev = hierarchy.prev
  let next = hierarchy.next
  let head = hierarchy.head

  if parent != NoHierarchyIdx and game.hierarchies[parent].head == idx:
    game.hierarchies[parent].head = next
  if prev != NoHierarchyIdx:
    game.hierarchies[prev].next = next
  if next != NoHierarchyIdx:
    game.hierarchies[next].prev = prev

  hierarchy = Hierarchy(
    head: head,
    prev: NoHierarchyIdx,
    next: NoHierarchyIdx,
    parent: NoHierarchyIdx
  )

proc allocTransform*(game: var Game; translation = vec2(0, 0); rotation = 0.Rad;
    scale = vec2(1, 1); parent = NoTransformIdx): TransformIdx =
  let transform = Transform2d(
    world: mat2d(),
    translation: translation,
    rotation: rotation,
    scale: scale,
    flags: {Dirty, Fresh}
  )
  let hierarchy = Hierarchy(
    head: NoHierarchyIdx,
    prev: NoHierarchyIdx,
    next: NoHierarchyIdx,
    parent: NoHierarchyIdx
  )
  let previous = Previous(
    position: point2(0, 0),
    rotation: 0.Rad,
    scale: vec2(1, 1)
  )
  let transformIdx = game.transforms.alloc(transform)
  let hierarchyIdx = game.hierarchies.alloc(hierarchy)
  let previousIdx = game.previous.alloc(previous)
  result = transformIdx

  if parent != NoTransformIdx:
    game.prependChild(parent, result)

proc freeTransform*(game: var Game; idx: TransformIdx) =
  if idx != NoTransformIdx:
    game.removeNode(idx)
    game.transforms.free(idx)
    game.hierarchies.free(idx.hierarchyIdx)
    game.previous.free(idx.previousIdx)

proc allocCollide*(game: var Game; size = vec2(0, 0)): CollideIdx =
  let value = Collide(
    size: size,
    min: point2(0, 0),
    max: point2(0, 0),
    center: point2(0, 0),
    collision: Collision(flags: {}, hit: vec2(0, 0))
  )
  result = game.colliders.alloc(value)

proc freeCollide*(game: var Game; idx: CollideIdx) =
  if idx != NoCollideIdx:
    game.colliders.free(idx)

proc allocDraw2d*(game: var Game; width, height: int32;
    color: array[4, uint8]): Draw2dIdx =
  let value = Draw2d(width: width, height: height, color: color)
  result = game.drawables.alloc(value)

proc freeDraw2d*(game: var Game; idx: Draw2dIdx) =
  if idx != NoDraw2dIdx:
    game.drawables.free(idx)

proc allocFade*(game: var Game; step = 0'f32): FadeIdx =
  let value = Fade(step: step)
  result = game.fades.alloc(value)

proc freeFade*(game: var Game; idx: FadeIdx) =
  if idx != NoFadeIdx:
    game.fades.free(idx)

proc allocMove*(game: var Game; direction = vec2(0, 0); speed = 10'f32): MoveIdx =
  let value = Move(direction: direction, speed: speed)
  result = game.moves.alloc(value)

proc freeMove*(game: var Game; idx: MoveIdx) =
  if idx != NoMoveIdx:
    game.moves.free(idx)

proc addActor*(game: var Game; kind: ActorKind; transform: TransformIdx;
    collide = NoCollideIdx; draw2d = NoDraw2dIdx; fade = NoFadeIdx;
    move = NoMoveIdx): ActorIdx =
  let actor = Actor(
    kind: kind,
    transform: transform,
    collide: collide,
    draw2d: draw2d,
    fade: fade,
    move: move
  )
  result = ActorIdx(game.actors.len.int32)
  game.actors.add(actor)

proc freeActorResources*(game: var Game; actor: Actor) =
  game.freeTransform(actor.transform)
  game.freeCollide(actor.collide)
  game.freeDraw2d(actor.draw2d)
  game.freeFade(actor.fade)
  game.freeMove(actor.move)

proc removeActor*(game: var Game; idx: ActorIdx) =
  if idx == NoActorIdx:
    return

  let lastIdx = ActorIdx(game.actors.high.int32)
  if game.paddle == idx:
    game.paddle = NoActorIdx
  elif idx != lastIdx and game.paddle == lastIdx:
    game.paddle = idx

  game.freeActorResources(game.actors[idx.int])
  game.actors.del(idx.int)

proc markDirty*(game: var Game; idx: TransformIdx) =
  if idx != NoTransformIdx:
    game.transforms[idx].flags.incl(Dirty)

# ---- blueprints ----

proc createBall*(game: var Game; x, y: float32) =
  let angle = PI.float32 + rand(1.0'f32) * PI.float32
  let transform = game.allocTransform(
    translation = vec2(x, y),
    scale = vec2(1, 1),
    parent = game.camera.transform
  )
  discard game.addActor(
    BallKind,
    transform,
    collide = game.allocCollide(vec2(20, 20)),
    draw2d = game.allocDraw2d(20, 20, [0'u8, 255, 0, 255]),
    move = game.allocMove(Vec2(x: cos(angle), y: sin(angle)), 14)
  )

proc createBrick*(game: var Game; x, y: float32; width, height: int32) =
  discard game.addActor(
    BrickKind,
    game.allocTransform(
      translation = vec2(x, y),
      scale = vec2(1, 1),
      parent = game.camera.transform
    ),
    collide = game.allocCollide(vec2(width.float32, height.float32)),
    draw2d = game.allocDraw2d(width, height, [255'u8, 255, 0, 255]),
    fade = game.allocFade(0)
  )

proc createExplosion*(game: var Game; x, y: float32) =
  let explosions = 32
  let step = TAU / explosions.float
  let fadeStep = 0.05
  for i in 0..<explosions:
    discard game.addActor(
      ParticleKind,
      game.allocTransform(
        translation = vec2(x, y),
        scale = vec2(1, 1),
        parent = game.camera.transform
      ),
      draw2d = game.allocDraw2d(20, 20, [255'u8, 255, 255, 255]),
      fade = game.allocFade(fadeStep),
      move = game.allocMove(
        Vec2(x: sin(step * i.float32), y: cos(step * i.float32)),
        20
      )
    )

proc createTrail*(game: var Game; x, y: float32) =
  discard game.addActor(
    TrailKind,
    game.allocTransform(
      translation = vec2(x, y),
      scale = vec2(1, 1),
      parent = game.camera.transform
    ),
    draw2d = game.allocDraw2d(20, 20, [0'u8, 255, 0, 255]),
    fade = game.allocFade(0.05)
  )

proc createPaddle*(game: var Game; x, y: float32) =
  game.paddle = game.addActor(
    PaddleKind,
    game.allocTransform(
      translation = vec2(x, y),
      scale = vec2(1, 1),
      parent = game.camera.transform
    ),
    collide = game.allocCollide(vec2(100, 20)),
    draw2d = game.allocDraw2d(100, 20, [255'u8, 0, 0, 255]),
    move = game.allocMove(vec2(0, 0), 20)
  )

proc createScene*(game: var Game) =
  let columnCount = 10
  let rowCount = 10
  let brickWidth = 50
  let brickHeight = 15
  let margin = 5

  let gridWidth = brickWidth * columnCount + margin * (columnCount - 1)
  let startingX = (game.windowWidth - gridWidth) div 2
  let startingY = 50

  game.camera = Camera(
    transform: game.allocTransform(
      translation = vec2(0, 0),
      scale = vec2(1, 1),
      parent = NoTransformIdx
    ),
    shake: Shake(duration: 0, strength: 10)
  )

  game.createPaddle(float32(game.windowWidth / 2), float32(game.windowHeight - 30))
  game.createBall(float32(game.windowWidth / 2), float32(game.windowHeight - 60))

  for row in 0..<rowCount:
    let y = startingY + row * (brickHeight + margin) + brickHeight div 2
    for col in 0..<columnCount:
      let x = startingX + col * (brickWidth + margin) + brickWidth div 2
      game.createBrick(x.float32, y.float32, brickWidth.int32, brickHeight.int32)

# ---- breakout/systems/collide.nim ----

proc computeAabb(transform: Transform2d; collide: var Collide) =
  collide.center = transform.world.origin
  collide.min = collide.center - collide.size / 2
  collide.max = collide.center + collide.size / 2

proc intersectAabb(a, b: Collide): bool =
  a.min.x < b.max.x and a.min.y < b.max.y and
    a.max.x > b.min.x and a.max.y > b.min.y

proc penetrateAabb(a, b: Collide): Vec2 =
  let distanceX = a.center.x - b.center.x
  let penetrationX = a.size.x / 2 + b.size.x / 2 - abs(distanceX)

  let distanceY = a.center.y - b.center.y
  let penetrationY = a.size.y / 2 + b.size.y / 2 - abs(distanceY)

  if penetrationX < penetrationY:
    result = vec2(penetrationX * sgn(distanceX).float32, 0)
  else:
    result = vec2(0, penetrationY * sgn(distanceY).float32)

proc prepareCollider(game: var Game; transformIdx: TransformIdx; collideIdx: CollideIdx) =
  template collider: untyped = game.colliders[collideIdx]
  collider.collision = Collision(flags: {}, hit: vec2(0, 0))
  computeAabb(game.transforms[transformIdx], collider)

proc updateCollision(game: var Game; aIdx, bIdx: CollideIdx) =
  let a = game.colliders[aIdx]
  let b = game.colliders[bIdx]
  if intersectAabb(a, b):
    let hit = penetrateAabb(a, b)
    game.colliders[aIdx].collision = Collision(flags: {Hit}, hit: hit)
    game.colliders[bIdx].collision = Collision(flags: {Hit}, hit: -hit)

proc sysCollide*(game: var Game) =
  if game.paddle != NoActorIdx:
    let paddle = game.actors[game.paddle.int]
    if paddle.kind == PaddleKind:
      game.prepareCollider(paddle.transform, paddle.collide)

  for actor in game.actors.items:
    if actor.collide != NoCollideIdx and actor.kind in {BallKind, BrickKind}:
      game.prepareCollider(actor.transform, actor.collide)

  for ball in game.actors.items:
    if ball.kind == BallKind:
      if game.paddle != NoActorIdx:
        let paddle = game.actors[game.paddle.int]
        if paddle.kind == PaddleKind:
          game.updateCollision(ball.collide, paddle.collide)

      for brick in game.actors.items:
        if brick.kind == BrickKind:
          game.updateCollision(ball.collide, brick.collide)

# ---- breakout/systems/controlball.nim ----

proc sysControlBall*(game: var Game) =
  let actorCount = game.actors.len
  for i in 0..<actorCount:
    template ball: untyped = game.actors[i]
    if ball.kind == BallKind:
      template collide: untyped = game.colliders[ball.collide]
      template move: untyped = game.moves[ball.move]
      template transform: untyped = game.transforms[ball.transform]

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

      game.markDirty(ball.transform)
      game.createTrail(transform.translation.x, transform.translation.y)

# ---- breakout/systems/controlbrick.nim ----

proc sysControlBrick*(game: var Game) =
  let actorCount = game.actors.len
  for i in 0..<actorCount:
    template brick: untyped = game.actors[i]
    if brick.kind == BrickKind and
        Hit in game.colliders[brick.collide].collision.flags:
      game.fades[brick.fade].step = 0.05
      if rand(1.0) > 0.98:
        game.createBall(
          float32(game.windowWidth / 2),
          float32(game.windowHeight / 2)
        )

# ---- breakout/systems/controlpaddle.nim ----

proc sysControlPaddle*(game: var Game) =
  if game.paddle == NoActorIdx:
    return

  let moveIdx = game.actors[game.paddle.int].move
  template move: untyped = game.moves[moveIdx]
  move.direction.x = 0

  if game.inputState[Left]:
    move.direction.x -= 1

  if game.inputState[Right]:
    move.direction.x += 1

# ---- breakout/systems/fade.nim ----

proc updateFading(game: var Game; transformIdx: TransformIdx; drawIdx: Draw2dIdx;
    fadeIdx: FadeIdx; kind: var ActorKind) =
  template transform: untyped = game.transforms[transformIdx]
  template draw: untyped = game.drawables[drawIdx]
  let fade = game.fades[fadeIdx]

  if draw.color[3] > 0:
    let step = 255 * fade.step
    draw.color[3] = draw.color[3] - step.uint8
    transform.scale.x -= fade.step
    transform.scale.y -= fade.step
    game.markDirty(transformIdx)

    if transform.scale.x <= 0:
      kind = DeadKind

proc cleanupDead*(game: var Game) =
  for i in countdown(game.actors.high, 0):
    if game.actors[i].kind == DeadKind:
      game.removeActor(ActorIdx(i))

proc sysFade*(game: var Game) =
  for actor in mitems(game.actors):
    if actor.kind != DeadKind and actor.fade != NoFadeIdx:
      game.updateFading(actor.transform, actor.draw2d, actor.fade, actor.kind)

# ---- breakout/systems/move.nim ----

proc updateTransform(game: var Game; transformIdx: TransformIdx; moveIdx: MoveIdx) =
  let move = game.moves[moveIdx]
  if move.direction.x != 0 or move.direction.y != 0:
    template transform: untyped = game.transforms[transformIdx]
    transform.translation.x += move.direction.x * move.speed
    transform.translation.y += move.direction.y * move.speed
    game.markDirty(transformIdx)

proc sysMove*(game: var Game) =
  for actor in game.actors.items:
    if actor.move != NoMoveIdx and actor.kind in {PaddleKind, BallKind, ParticleKind}:
      game.updateTransform(actor.transform, actor.move)

# ---- breakout/systems/shake.nim ----

proc sysShake*(game: var Game) =
  let transformIdx = game.camera.transform
  template transform: untyped = game.transforms[transformIdx]
  template shake: untyped = game.camera.shake

  if shake.duration > 0:
    shake.duration -= 0.01
    transform.translation.x = shake.strength - rand(shake.strength * 2)
    transform.translation.y = shake.strength - rand(shake.strength * 2)

    game.clearColor[0] = rand(255).uint8
    game.clearColor[1] = rand(255).uint8
    game.clearColor[2] = rand(255).uint8
    game.markDirty(transformIdx)

    if shake.duration <= 0:
      shake.duration = 0
      transform.translation.x = 0
      transform.translation.y = 0
      game.clearColor[0] = 0
      game.clearColor[1] = 0
      game.clearColor[2] = 0
      game.markDirty(transformIdx)

# ---- breakout/systems/transform2d.nim ----

proc updateTransformWorld(game: var Game; idx: TransformIdx) =
  template transform: untyped = game.transforms[idx]
  template previous: untyped = game.previous[idx.previousIdx]

  if Fresh in transform.flags:
    transform.flags.excl(Fresh)
  else:
    previous.position = transform.world.origin
    previous.rotation = transform.world.rotation
    previous.scale = transform.world.scale
    transform.flags.incl(HasPrevious)
    transform.flags.excl(Dirty)

  let local = compose(transform.scale, transform.rotation, transform.translation)
  let parent = game.parent(idx)
  if parent != NoTransformIdx:
    let parentTransform = game.transforms[parent]
    transform.world = parentTransform.world * local
  else:
    transform.world = local

proc sysTransform2d*(game: var Game) =
  var stack: seq[TransformIdx] = @[]
  var current = game.camera.transform

  while current != NoTransformIdx:
    let sibling = game.nextSibling(current)
    if sibling != NoTransformIdx:
      stack.add(sibling)

    if game.transforms[current].flags.intersects({Dirty, Fresh}):
      game.updateTransformWorld(current)

    let child = game.firstChild(current)
    if child != NoTransformIdx:
      current = child
    elif stack.len > 0:
      current = stack.pop()
    else:
      current = NoTransformIdx
