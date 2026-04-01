type
  BenchScale* = object
    name*: string
    columns*: int
    rows*: int

const
  BenchScales* = [
    BenchScale(name: "small", columns: 10, rows: 10),
    BenchScale(name: "medium", columns: 20, rows: 15),
    BenchScale(name: "large", columns: 30, rows: 20),
    BenchScale(name: "xlarge", columns: 40, rows: 25),
    BenchScale(name: "xxlarge", columns: 50, rows: 30)
  ]

proc findBenchScale*(name: string): BenchScale =
  for scale in BenchScales:
    if scale.name == name:
      return scale
  raise newException(ValueError, "unknown benchmark scale: " & name)
