import Carbon

// A small boundary lets controller tests run without changing the user's input source.
struct InputSourceAccess {
    var currentID: () -> String?
    var availableIDs: () -> [String]
    var select: (String) -> OSStatus

    static let system = InputSourceAccess(
        currentID: { InputSources.current()?.id },
        availableIDs: { InputSources.all().map(\.id) },
        select: { id in
            guard let source = InputSources.all().first(where: { $0.id == id }) else { return OSStatus(paramErr) }
            return TISSelectInputSource(source.reference)
        }
    )
}
