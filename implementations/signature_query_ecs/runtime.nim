import std/[math, random]
import ../../bench_sizes
import ../../shared/[headless_raylib, vmath]
# ---- entities ----
type
  Entity* = distinct EntityImpl
  EntityImpl* = uint16

const
  VersionBits = 3
  IndexBits = sizeof(Entity) * 8 - VersionBits
  IndexMask = 1 shl IndexBits - 1
  InvalidId* = Entity(IndexMask) # a sentinel value to represent an invalid entity
  MaxEntities* = IndexMask

template idx*(e: Entity): int = e.int and IndexMask
template version*(e: Entity): EntityImpl = e.EntityImpl shr IndexBits
template toEntity*(idx, v: EntityImpl): Entity = Entity(v shl IndexBits or idx)

proc `==`*(a, b: Entity): bool {.borrow.}
proc `$`*(e: Entity): string =
  "Entity(i: " & $e.idx & ", v: " & $e.version & ")"

# ---- type-erased columns ----
from typetraits import supportsCopyMem

proc allocColumn[T](count: int): pointer =
  let size = count * sizeof(T)
  when not supportsCopyMem(T):
    result = alloc0(size)
  else:
    result = alloc(size)

proc freeColumn[T](p: pointer; count: int) =
  if p != nil:
    when not supportsCopyMem(T):
      let data = cast[ptr UncheckedArray[T]](p)
      for i in 0..<count:
        `=destroy`(data[i])
    dealloc(p)

# ---- slottables ----

type
  Entry*[T] = tuple
    e: Entity
    value: T
  SlotTable*[T] = object
    freeHead: int
    slots: seq[Entity]
    data: seq[Entry[T]]

proc initSlotTableOfCap*[T](capacity: Natural): SlotTable[T] =
  result = SlotTable[T](
    data: newSeqOfCap[Entry[T]](capacity),
    slots: newSeqOfCap[Entity](capacity),
    freeHead: 0
  )

proc len*[T](x: SlotTable[T]): int {.inline.} =
  result = x.data.len

proc contains*[T](x: SlotTable[T], e: Entity): bool =
  result = e.idx < x.slots.len and
      x.slots[e.idx].version == e.version

proc incl*[T](x: var SlotTable[T], value: T): Entity =
  if x.len + 1 == MaxEntities:
    raise newException(RangeDefect, "SlotTable number of elements overflow")
  let idx = x.freeHead
  if idx < x.slots.len:
    template slot: untyped = x.slots[idx]
    let occupiedVersion = slot.version or 1
    result = toEntity(idx.EntityImpl, occupiedVersion)
    x.data.add((e: result, value: value))
    x.freeHead = slot.idx
    slot = toEntity(x.data.high.EntityImpl, occupiedVersion)
  else:
    result = toEntity(idx.EntityImpl, 1)
    x.data.add((e: result, value: value))
    x.slots.add(toEntity(x.data.high.EntityImpl, 1))
    x.freeHead = x.slots.len

proc freeSlot[T](x: var SlotTable[T], slotIdx: int): int {.inline.} =
  # Helper function to add a slot to the freelist. Returns the index that
  # was stored in the slot.
  template slot: untyped = x.slots[slotIdx]
  result = slot.idx
  slot = toEntity(x.freeHead.EntityImpl, slot.version + 1)
  x.freeHead = slotIdx

proc delFromSlot[T](x: var SlotTable[T], slotIdx: int) {.inline.} =
  # Helper function to remove a value from a slot and make the slot free.
  # Returns the value deld.
  let valueIdx = x.freeSlot(slotIdx)
  # Remove values/slot_indices by swapping to end.
  x.data[valueIdx] = move(x.data[x.data.high])
  x.data.shrink(x.data.high)
  # Did something take our place? Update its slot to new position.
  if x.data.len > valueIdx:
    let kIdx = x.data[valueIdx].e.idx
    template slot: untyped = x.slots[kIdx]
    slot = toEntity(valueIdx.EntityImpl, slot.version)

proc del*[T](x: var SlotTable[T], e: Entity) =
  if x.contains(e):
    x.delFromSlot(e.idx)

proc clear*[T](x: var SlotTable[T]) =
  x.freeHead = 0
  x.slots.shrink(0)
  x.data.shrink(0)

template get(x, e) =
  template slot: untyped = x.slots[e.idx]
  if e.idx >= x.slots.len or slot.version != e.version:
    raise newException(KeyError, "Entity not in SlotTable")
  # This is safe because we only store valid indices.
  let idx = slot.idx
  result = x.data[idx].value

proc `[]`*[T](x: SlotTable[T], e: Entity): T =
  get(x, e)

proc `[]`*[T](x: var SlotTable[T], e: Entity): var T =
  get(x, e)

iterator pairs*[T](x: SlotTable[T]): Entry[T] =
  for i in 0 ..< x.len:
    yield x.data[i]

# ---- gametypes ----

type
  Input* = enum
    Right, Left

  CollisionFlag* = enum
    Hit

  HasComponent* = enum
    HasCollide,
    HasControlBall,
    HasControlBrick,
    HasControlPaddle,
    HasDirty,
    HasDraw2d,
    HasFade,
    HasFresh,
    HasHierarchy,
    HasMove,
    HasPrevious,
    HasShake,
    HasTransform2d

  Collision* = object
    flags*: set[CollisionFlag]
    hit*: Vec2

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

  Hierarchy* = object
    head*: Entity        # the entity identifier of the first child, if any.
    prev*, next*: Entity # the prev/next sibling in the list of children for the parent.
    parent*: Entity      # the entity identifier of the parent, if any.

  Move* = object
    direction*: Vec2
    speed*: float32

  Previous* = object
    position*: Point2 # position at the previous physics state
    rotation*: Rad    # rotation at the previous physics state
    scale*: Vec2      # scale at the previous physics state

  Shake* = object
    duration*: float32
    strength*: float32

  Transform2d* = object
    world*: Mat2d      # Matrix relative to the world
    translation*: Vec2 # local translation relative to the parent
    rotation*: Rad     # local rotation relative to the parent
    scale*: Vec2       # local scale relative to the parent

  World* = object
    signature*: SlotTable[set[HasComponent]]
    columns*: array[HasComponent, pointer]

  Game* = object
    world*: World

    toDelete*: seq[Entity]
    inputState*: array[Input, bool]
    clearColor*: array[4, uint8]
    camera*: Entity

    isRunning*: bool
    windowWidth*, windowHeight*: int32
    tickId*: int

    raylib*: RaylibContext

proc `=destroy`*(world: var World) =
  freeColumn[Collide](world.columns[HasCollide], MaxEntities)
  freeColumn[Draw2d](world.columns[HasDraw2d], MaxEntities)
  freeColumn[Fade](world.columns[HasFade], MaxEntities)
  freeColumn[Hierarchy](world.columns[HasHierarchy], MaxEntities)
  freeColumn[Move](world.columns[HasMove], MaxEntities)
  freeColumn[Previous](world.columns[HasPrevious], MaxEntities)
  freeColumn[Shake](world.columns[HasShake], 1)
  freeColumn[Transform2d](world.columns[HasTransform2d], MaxEntities)

proc initWorld*(): World =
  result = World(
    signature: initSlotTableOfCap[set[HasComponent]](MaxEntities)
  )
  result.columns[HasCollide] = allocColumn[Collide](MaxEntities)
  result.columns[HasDraw2d] = allocColumn[Draw2d](MaxEntities)
  result.columns[HasFade] = allocColumn[Fade](MaxEntities)
  result.columns[HasHierarchy] = allocColumn[Hierarchy](MaxEntities)
  result.columns[HasMove] = allocColumn[Move](MaxEntities)
  result.columns[HasPrevious] = allocColumn[Previous](MaxEntities)
  result.columns[HasShake] = allocColumn[Shake](1)
  result.columns[HasTransform2d] = allocColumn[Transform2d](MaxEntities)

proc componentColumn[T](world: World; has: static[HasComponent]): ptr UncheckedArray[T] {.inline.} =
  cast[ptr UncheckedArray[T]](world.columns[has])

# ---- utils ----

proc createEntity*(world: var World): Entity =
  result = world.signature.incl({})

iterator queryAll*(world: World, parent: Entity, query: set[HasComponent]): Entity =
  template hierarchy: untyped = componentColumn[Hierarchy](world, HasHierarchy)[entity.idx]

  var frontier = @[parent]
  while frontier.len > 0:
    let entity = frontier.pop()
    if query <= world.signature[entity]:
      yield entity

    var childId = hierarchy.head
    while childId != InvalidId:
      template childHierarchy: untyped = componentColumn[Hierarchy](world, HasHierarchy)[childId.idx]

      frontier.add(childId)
      childId = childHierarchy.next

template `?=`(name, value): bool = (let name = value; name != InvalidId)
proc prepend*(world: var World, parentId, entity: Entity) =
  template hierarchy: untyped = componentColumn[Hierarchy](world, HasHierarchy)[entity.idx]
  template parent: untyped = componentColumn[Hierarchy](world, HasHierarchy)[parentId.idx]
  template headSibling: untyped = componentColumn[Hierarchy](world, HasHierarchy)[headSiblingId.idx]

  hierarchy.prev = InvalidId
  hierarchy.next = parent.head
  if headSiblingId ?= parent.head:
    assert headSibling.prev == InvalidId
    headSibling.prev = entity
  parent.head = entity

proc removeNode*(world: var World, entity: Entity) =
  template hierarchy: untyped = componentColumn[Hierarchy](world, HasHierarchy)[entity.idx]
  template parent: untyped = componentColumn[Hierarchy](world, HasHierarchy)[parentId.idx]
  template nextSibling: untyped = componentColumn[Hierarchy](world, HasHierarchy)[nextSiblingId.idx]
  template prevSibling: untyped = componentColumn[Hierarchy](world, HasHierarchy)[prevSiblingId.idx]

  if parentId ?= hierarchy.parent:
    if entity == parent.head: parent.head = hierarchy.next
  if nextSiblingId ?= hierarchy.next: nextSibling.prev = hierarchy.prev
  if prevSiblingId ?= hierarchy.prev: prevSibling.next = hierarchy.next

proc delete*(game: var Game, entity: Entity) =
  for entity in queryAll(game.world, entity, {HasHierarchy}):
    removeNode(game.world, entity)
    game.toDelete.add(entity)
  #else: game.toDelete.add(entity)

proc cleanup*(game: var Game) =
  for entity in game.toDelete.items:
    game.world.signature.del(entity)
  game.toDelete.shrink(0)

proc rmComponent*(world: var World, entity: Entity, has: HasComponent) =
  world.signature[entity].excl has

# ---- mixins ----

template mixBody(has) =
  world.signature[entity].incl has

proc mixCollide*(world: var World, entity: Entity, size = vec2(0, 0)) =
  mixBody HasCollide
  componentColumn[Collide](world, HasCollide)[entity.idx] = Collide(
    size: size,
    collision: Collision(flags: {}, hit: vec2(0, 0))
  )

proc mixControlBall*(world: var World, entity: Entity) =
  mixBody HasControlBall

proc mixControlBrick*(world: var World, entity: Entity) =
  mixBody HasControlBrick

proc mixControlPaddle*(world: var World, entity: Entity) =
  mixBody HasControlPaddle

proc mixDirty*(world: var World, entity: Entity) =
  mixBody HasDirty

proc mixDraw2d*(world: var World, entity: Entity; width = 100'i32;
    height = 100'i32; color = [255'u8, 0, 255, 255]) =
  mixBody HasDraw2d
  componentColumn[Draw2d](world, HasDraw2d)[entity.idx] =
    Draw2d(width: width, height: height, color: color)

proc mixFade*(world: var World, entity: Entity, step = 0'f32) =
  mixBody HasFade
  componentColumn[Fade](world, HasFade)[entity.idx] = Fade(step: step)

proc mixFresh*(world: var World, entity: Entity) =
  mixBody HasFresh

proc mixHierarchy*(world: var World, entity: Entity, parent = InvalidId) =
  mixBody HasHierarchy
  componentColumn[Hierarchy](world, HasHierarchy)[entity.idx] =
    Hierarchy(head: InvalidId, prev: InvalidId,
      next: InvalidId, parent: parent)
  if parent != InvalidId: prepend(world, parent, entity)

proc mixMove*(world: var World, entity: Entity, direction = vec2(0, 0), speed = 10'f32) =
  mixBody HasMove
  componentColumn[Move](world, HasMove)[entity.idx] = Move(direction: direction, speed: speed)

proc mixPrevious*(world: var World, entity: Entity, position = point2(0, 0),
    rotation = 0.Rad, scale = vec2(1, 1)) =
  mixBody HasPrevious
  componentColumn[Previous](world, HasPrevious)[entity.idx] =
    Previous(position: position,
      rotation: rotation, scale: scale)

proc mixShake*(world: var World, entity: Entity, duration = 1'f32, strength = 0'f32) =
  template shake: untyped = componentColumn[Shake](world, HasShake)[0]
  mixBody HasShake
  shake = Shake(duration: duration, strength: strength)

proc mixTransform2d*(world: var World, entity: Entity; trworld = mat2d();
    translation = vec2(0, 0); rotation = 0.Rad; scale = vec2(1, 1);
    parent = InvalidId) =
  template transform: untyped =
    componentColumn[Transform2d](world, HasTransform2d)[entity.idx]
  mixBody HasTransform2d
  transform = Transform2d(world: trworld, translation: translation,
    rotation: rotation, scale: scale)
  mixHierarchy(world, entity, parent)
  mixDirty(world, entity)
  mixFresh(world, entity)

# ---- blueprints ----

proc createBall*(world: var World, parent: Entity, x, y: float32): Entity =
  let angle = Pi.float32 + rand(1.0'f32) * Pi.float32
  let entity = createEntity(world)
  mixTransform2d(world, entity, mat2d(), Vec2(x: x, y: y), Rad(0), vec2(1, 1), parent)
  mixCollide(world, entity, Vec2(x: 20.0, y: 20.0))
  mixControlBall(world, entity)
  mixDraw2d(world, entity, 20, 20, [0'u8, 255, 0, 255])
  mixMove(world, entity, Vec2(x: cos(angle), y: sin(angle)), 14)
  result = entity

proc createBrick*(world: var World, parent: Entity, x, y: float32, width, height: int32): Entity =
  let entity = createEntity(world)
  mixTransform2d(world, entity, mat2d(), Vec2(x: x, y: y), Rad(0), vec2(1, 1), parent)
  mixCollide(world, entity, Vec2(x: width.float32, y: height.float32))
  mixControlBrick(world, entity)
  mixDraw2d(world, entity, width, height, [255'u8, 255, 0, 255])
  mixFade(world, entity, 0.0)
  result = entity

proc createExplosion*(world: var World, parent: Entity, x, y: float32): Entity =
  let explosions = 32
  let step = Tau / explosions.float
  let fadeStep = 0.05
  for i in 0 ..< explosions:
    let particle = createEntity(world)
    mixTransform2d(world, particle, mat2d(), Vec2(x: x, y: y), Rad(0), vec2(1, 1), parent)
    mixDraw2d(world, particle, 20, 20, [255'u8, 255, 255, 255])
    mixFade(world, particle, fadeStep)
    mixMove(world, particle, Vec2(x: sin(step * i.float32), y: cos(step * i.float32)), 20)
  result = InvalidId

proc createTrail*(world: var World, parent: Entity, x, y: float32): Entity =
  let entity = createEntity(world)
  mixTransform2d(world, entity, mat2d(), Vec2(x: x, y: y), Rad(0), vec2(1, 1), parent)
  mixDraw2d(world, entity, 20, 20, [0'u8, 255, 0, 255])
  mixFade(world, entity, 0.05)
  result = entity

proc createPaddle*(world: var World, parent: Entity, x, y: float32): Entity =
  let entity = createEntity(world)
  mixTransform2d(world, entity, mat2d(), Vec2(x: x, y: y), Rad(0), vec2(1, 1), parent)
  mixCollide(world, entity, Vec2(x: 100, y: 20))
  mixControlPaddle(world, entity)
  mixDraw2d(world, entity, 100, 20, [255'u8, 0, 0, 255])
  mixMove(world, entity, vec2(0, 0), 20)
  result = entity

proc createScene*(game: var Game; scale: BenchScale) =
  let columnCount = scale.columns
  let rowCount = scale.rows
  let brickWidth = 50
  let brickHeight = 15
  let margin = 5

  let gridWidth = brickWidth * columnCount + margin * (columnCount - 1)
  let startingX = (game.windowWidth - gridWidth) div 2
  let startingY = 50

  let camera = createEntity(game.world)
  mixTransform2d(game.world, camera, mat2d(), vec2(0, 0), Rad(0), vec2(1, 1), InvalidId)
  mixShake(game.world, camera, 0, 10)
  discard createPaddle(game.world, camera, float32(game.windowWidth / 2), float32(game.windowHeight - 30))
  discard createBall(game.world, camera, float32(game.windowWidth / 2), float32(game.windowHeight - 60))
  for row in 0 ..< rowCount:
    let y = startingY + row * (brickHeight + margin) + brickHeight div 2
    for col in 0 ..< columnCount:
      let x = startingX + col * (brickWidth + margin) + brickWidth div 2
      discard createBrick(game.world, camera, x.float32, y.float32, brickWidth.int32, brickHeight.int32)
  game.camera = camera

# ---- temp/breakout/systems/collide.nim ----

const
  ColliderQuery = {HasTransform2d, HasCollide}
  BallQuery = ColliderQuery + {HasControlBall}
  BrickQuery = ColliderQuery + {HasControlBrick}
  PaddleQuery = ColliderQuery + {HasControlPaddle}

proc computeAabb(transform: Transform2d, collide: var Collide) =
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

proc updateCollision(game: var Game, colliderId, otherId: Entity) =
  template collider: untyped = componentColumn[Collide](game.world, HasCollide)[colliderId.idx]
  template other: untyped = componentColumn[Collide](game.world, HasCollide)[otherId.idx]

  if intersectAabb(collider, other):
    let hit = penetrateAabb(collider, other)
    collider.collision = Collision(flags: {Hit}, hit: hit)
    other.collision = Collision(flags: {Hit}, hit: -hit)

proc sysCollide*(game: var Game) =
  var paddle = InvalidId

  for colliderId, signature in game.world.signature.pairs:
    if ColliderQuery <= signature:
      template transform: untyped =
        componentColumn[Transform2d](game.world, HasTransform2d)[colliderId.idx]
      template collider: untyped =
        componentColumn[Collide](game.world, HasCollide)[colliderId.idx]

      collider.collision = Collision(flags: {}, hit: vec2(0, 0))
      computeAabb(transform, collider)
      if PaddleQuery <= signature:
        paddle = colliderId

  for ballId, ballSignature in game.world.signature.pairs:
    if BallQuery <= ballSignature:
      if paddle != InvalidId:
        game.updateCollision(ballId, paddle)
      for brickId, brickSignature in game.world.signature.pairs:
        if BrickQuery <= brickSignature:
          game.updateCollision(ballId, brickId)

# ---- temp/breakout/systems/controlball.nim ----

const ControlBallQuery = {HasTransform2d, HasMove, HasCollide, HasControlBall}

proc updateControlBall(game: var Game, entity: Entity) =
  template collide: untyped = componentColumn[Collide](game.world, HasCollide)[entity.idx]
  template move: untyped = componentColumn[Move](game.world, HasMove)[entity.idx]
  template transform: untyped =
    componentColumn[Transform2d](game.world, HasTransform2d)[entity.idx]

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
    let collision = collide.collision
    if HasShake in game.world.signature[game.camera]:
      template cameraShake: untyped = componentColumn[Shake](game.world, HasShake)[0]
      cameraShake.duration = 0.1

    if collision.hit.x != 0:
      transform.translation.x += collision.hit.x
      move.direction.x *= -1

    if collision.hit.y != 0:
      transform.translation.y += collision.hit.y
      move.direction.y *= -1

    discard game.world.createExplosion(game.camera, transform.translation.x,
        transform.translation.y)

  discard game.world.createTrail(game.camera, transform.translation.x,
      transform.translation.y)

proc sysControlBall*(game: var Game) =
  for entity, signature in game.world.signature.pairs:
    if ControlBallQuery <= signature:
      updateControlBall(game, entity)

# ---- temp/breakout/systems/controlbrick.nim ----

const ControlBrickQuery = {HasControlBrick, HasCollide, HasFade}

proc updateControlBrick(game: var Game, entity: Entity) =
  template collide: untyped = componentColumn[Collide](game.world, HasCollide)[entity.idx]
  template fade: untyped = componentColumn[Fade](game.world, HasFade)[entity.idx]

  if Hit in collide.collision.flags:
    fade.step = 0.05

    if rand(1.0) > 0.98:
      discard game.world.createBall(game.camera, float32(game.windowWidth / 2),
            float32(game.windowHeight / 2))

proc sysControlBrick*(game: var Game) =
  for entity, signature in game.world.signature.pairs:
    if ControlBrickQuery <= signature:
      updateControlBrick(game, entity)

# ---- temp/breakout/systems/controlpaddle.nim ----

const ControlPaddleQuery = {HasMove, HasControlPaddle}

proc updateControlPaddle(game: var Game, entity: Entity) =
  template move: untyped = componentColumn[Move](game.world, HasMove)[entity.idx]

  move.direction.x = 0

  if game.inputState[Left]:
    move.direction.x -= 1

  if game.inputState[Right]:
    move.direction.x += 1

proc sysControlPaddle*(game: var Game) =
  for entity, signature in game.world.signature.pairs:
    if ControlPaddleQuery <= signature:
      updateControlPaddle(game, entity)

# ---- temp/breakout/systems/fade.nim ----

const FadeQuery = {HasTransform2d, HasFade, HasDraw2d}

proc updateFade(game: var Game, entity: Entity) =
  template transform: untyped =
    componentColumn[Transform2d](game.world, HasTransform2d)[entity.idx]
  template fade: untyped = componentColumn[Fade](game.world, HasFade)[entity.idx]
  template draw: untyped = componentColumn[Draw2d](game.world, HasDraw2d)[entity.idx]

  if draw.color[3] > 0:
    let step = 255 * fade.step
    draw.color[3] = draw.color[3] - step.uint8
    transform.scale.x -= fade.step
    transform.scale.y -= fade.step

    game.world.mixDirty(entity)

    if transform.scale.x <= 0:
      game.delete(entity)

proc sysFade*(game: var Game) =
  for entity, signature in game.world.signature.pairs:
    if FadeQuery <= signature:
      updateFade(game, entity)

# ---- temp/breakout/systems/move.nim ----

const MoveQuery = {HasTransform2d, HasMove}

proc updateMove(game: var Game, entity: Entity) =
  template transform: untyped =
    componentColumn[Transform2d](game.world, HasTransform2d)[entity.idx]
  template move: untyped = componentColumn[Move](game.world, HasMove)[entity.idx]

  if move.direction.x != 0 or move.direction.y != 0:
    transform.translation.x += move.direction.x * move.speed
    transform.translation.y += move.direction.y * move.speed

    game.world.mixDirty(entity)

proc sysMove*(game: var Game) =
  for entity, signature in game.world.signature.pairs:
    if MoveQuery <= signature:
      updateMove(game, entity)

# ---- temp/breakout/systems/shake.nim ----

const ShakeQuery = {HasTransform2d, HasShake}

proc updateShake(game: var Game, entity: Entity) =
  template transform: untyped =
    componentColumn[Transform2d](game.world, HasTransform2d)[entity.idx]
  template shake: untyped = componentColumn[Shake](game.world, HasShake)[0]

  if shake.duration > 0:
    shake.duration -= 0.01
    transform.translation.x = shake.strength - rand(shake.strength * 2)
    transform.translation.y = shake.strength - rand(shake.strength * 2)

    game.clearColor[0] = rand(255).uint8
    game.clearColor[1] = rand(255).uint8
    game.clearColor[2] = rand(255).uint8

    game.world.mixDirty(entity)

    if shake.duration <= 0:
      shake.duration = 0
      transform.translation.x = 0
      transform.translation.y = 0
      game.clearColor[0] = 0
      game.clearColor[1] = 0
      game.clearColor[2] = 0

proc sysShake*(game: var Game) =
  let signature = game.world.signature[game.camera]
  if ShakeQuery <= signature:
    updateShake(game, game.camera)

# ---- temp/breakout/systems/transform2d.nim ----

const TransformQuery = {HasTransform2d, HasHierarchy, HasDirty}

proc updateTransformWorld(world: var World, entity: Entity) =
  template `?=`(name, value): bool = (let name = value; name != InvalidId)
  template transform: untyped = componentColumn[Transform2d](world, HasTransform2d)[entity.idx]
  template hierarchy: untyped = componentColumn[Hierarchy](world, HasHierarchy)[entity.idx]

  if HasFresh notin world.signature[entity]:
    let position = transform.world.origin
    let rotation = transform.world.rotation
    let scale = transform.world.scale

    world.mixPrevious(entity, position, rotation, scale)
    world.rmComponent(entity, HasDirty)
  else:
    world.rmComponent(entity, HasFresh)

  let local = compose(transform.scale, transform.rotation, transform.translation)
  if parentId ?= hierarchy.parent:
    template parentTransform: untyped =
      componentColumn[Transform2d](world, HasTransform2d)[parentId.idx]
    transform.world = parentTransform.world * local
  else:
    transform.world = local

proc sysTransform2d*(game: var Game) =
  for entity in queryAll(game.world, game.camera, TransformQuery):
    updateTransformWorld(game.world, entity)
