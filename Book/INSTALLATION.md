# Installation

getting flight into your project is super easy. we use swift package manager (spm) so there's no messy config.

### Step 1: Add The Dependency

pop open your `Package.swift` and drop this in your dependencies array:

```swift
dependencies: [
    // grab the latest version from github
    .package(url: "https://github.com/debaucheryparty/Flight.git", from: "0.1.0")
]
```

### Step 2: Link The Target

don't forget to link the `Flight` library to your actual executable target so you can import it:

```swift
.executableTarget(
    name: "MyAwesomeBot",
    dependencies: [
        .product(name: "Flight", package: "Flight")
    ],
    // you gotta enable c++ interoperability for the encryption stuff to work smoothly!
    swiftSettings: [
        .interoperabilityMode(.Cxx)
    ]
)
```

### Step 3: Build It

run `swift build` and grab a coffee. it'll pull down the discord encryption stuff and nio dependencies automatically.

once it's done, just add `import Flight` at the top of your swift files and you're golden! head over to the [Usage guide](USAGE.md) to see how to actually play music.
