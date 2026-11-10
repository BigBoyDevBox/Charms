import Foundation

/// Mixed-skin-tone multi-person sequences whose tone-free form is not a
/// fully-qualified row in emoji-test.txt, so key matching cannot find their
/// base. The table maps each such family key (the sequence with skin-tone
/// modifiers and U+FE0F removed) to the key of the fully-qualified base that
/// shares its emoji family name, such as `women holding hands` or `kiss`.
/// Any other variant left without a base is a build error, so a future emoji
/// release cannot silently misplace these.
enum MultiPersonFamilies {
    static let baseByVariantKey: [[UInt32]: [UInt32]] = [
        [0x1FAF1, 0x200D, 0x1FAF2]: [0x1F91D],                    // handshake
        [0x1F9D1, 0x200D, 0x1F430, 0x200D, 0x1F9D1]: [0x1F46F],   // people with bunny ears
        [0x1F468, 0x200D, 0x1F430, 0x200D, 0x1F468]:
            [0x1F46F, 0x200D, 0x2642],                          // men with bunny ears
        [0x1F469, 0x200D, 0x1F430, 0x200D, 0x1F469]:
            [0x1F46F, 0x200D, 0x2640],                          // women with bunny ears
        [0x1F9D1, 0x200D, 0x1FAEF, 0x200D, 0x1F9D1]: [0x1F93C],   // people wrestling
        [0x1F468, 0x200D, 0x1FAEF, 0x200D, 0x1F468]:
            [0x1F93C, 0x200D, 0x2642],                          // men wrestling
        [0x1F469, 0x200D, 0x1FAEF, 0x200D, 0x1F469]:
            [0x1F93C, 0x200D, 0x2640],                          // women wrestling
        [0x1F469, 0x200D, 0x1F91D, 0x200D, 0x1F469]: [0x1F46D],   // women holding hands
        [0x1F469, 0x200D, 0x1F91D, 0x200D, 0x1F468]: [0x1F46B],   // woman and man holding hands
        [0x1F468, 0x200D, 0x1F91D, 0x200D, 0x1F468]: [0x1F46C],   // men holding hands
        [0x1F9D1, 0x200D, 0x2764, 0x200D, 0x1F48B, 0x200D, 0x1F9D1]:
            [0x1F48F],                                          // kiss: person, person
        [0x1F9D1, 0x200D, 0x2764, 0x200D, 0x1F9D1]: [0x1F491],    // couple with heart: person, person
    ]
}
