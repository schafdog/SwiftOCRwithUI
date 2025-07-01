import Foundation

func main() {

    let args = CommandLine.arguments

    if args.count < 2 {
        print("Usage: DateRenamer <directory>")
        exit(1)
    }

    let fileManager = FileManager.default
    let currentDirectory = args[1]

    print("Scanning directory: \(currentDirectory)")

    do {
        let files = try fileManager.contentsOfDirectory(atPath: currentDirectory)
        let textFiles = files.filter { $0.hasSuffix(".txt") }

        print("Found \(textFiles.count) text files")

        for textFile in textFiles {
            let textFilePath = "\(currentDirectory)/\(textFile)"
            let baseName = String(textFile.dropLast(4))  // Remove .txt extension
            let jpegFile = "\(baseName).jpg"
            let jpegFilePath = "\(currentDirectory)/\(jpegFile)"

            // Check if corresponding JPEG exists
            guard fileManager.fileExists(atPath: jpegFilePath) else {
                print("No corresponding JPEG found for \(textFile)")
                continue
            }

            // Read the text file
            guard let content = try? String(contentsOfFile: textFilePath, encoding: .utf8) else {
                print("Could not read \(textFile)")
                continue
            }

            // Parse the date from the content
            let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

            if let date = parseDate(from: trimmedContent) {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyyMMdd"
                let newFileName = "\(dateFormatter.string(from: date)).jpg"
                let newFilePath = "\(currentDirectory)/\(newFileName)"

                // Check if target file already exists
                if fileManager.fileExists(atPath: newFilePath) {
                    print("Target file \(newFileName) already exists, skipping \(jpegFile)")
                    continue
                }

                // Rename the file
                do {
                    try fileManager.moveItem(atPath: jpegFilePath, toPath: newFilePath)
                    print("Renamed \(jpegFile) → \(newFileName)")
                    try fileManager.removeItem(atPath: textFilePath)
                } catch {
                    print("Failed to rename \(jpegFile): \(error)")
                }
            } else {
                print("Could not parse date from \(textFile): '\(trimmedContent)'")
            }
        }
    } catch {
        print("Error scanning directory: \(error)")
    }
}

func parseDate(from text: String) -> Date? {
    // Try to parse m/d/yy format
    let components = text.components(separatedBy: "/")

    guard components.count == 3,
        let month = Int(components[0]),
        let day = Int(components[1]),
        let year = Int(components[2])
    else {
        return nil
    }

    // Validate ranges
    guard month >= 1 && month <= 12,
        day >= 1 && day <= 31,
        year >= 0 && year <= 99
    else {
        return nil
    }

    // Convert 2-digit year to 4-digit year
    // Assuming years 00-29 are 2000-2029, and 30-99 are 1930-1999
    let fullYear = year <= 29 ? 2000 + year : 1900 + year

    var dateComponents = DateComponents()
    dateComponents.year = fullYear
    dateComponents.month = month
    dateComponents.day = day

    let calendar = Calendar.current
    return calendar.date(from: dateComponents)
}

main()
