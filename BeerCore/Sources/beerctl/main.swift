import BeerCore
import Foundation

// beerctl — small helper CLI. Its job: emit the BeerStyle presets as JSON so
// the WebGL preview harness renders with exactly the same numbers as the iOS app.

let command = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "help"

switch command {
case "dump-styles":
    do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(BeerStyle.all)
        FileHandle.standardOutput.write(data)
        print()
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        exit(1)
    }
default:
    FileHandle.standardError.write(Data("usage: beerctl dump-styles\n".utf8))
    exit(2)
}
