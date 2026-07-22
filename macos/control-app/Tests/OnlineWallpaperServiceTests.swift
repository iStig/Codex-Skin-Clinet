import Foundation

@main
struct OnlineWallpaperServiceTests {
  static func main() throws {
    let fixture = #"""
    {
      "query": {
        "pages": [
          {
            "pageid": 10,
            "title": "File:Mountain_Lake.jpg",
            "imageinfo": [{
              "size": 4200000,
              "width": 6000,
              "height": 3375,
              "url": "https://upload.wikimedia.org/example/Mountain_Lake.jpg",
              "descriptionurl": "https://commons.wikimedia.org/wiki/File:Mountain_Lake.jpg",
              "thumburl": "https://upload.wikimedia.org/example/thumb/Mountain_Lake.jpg",
              "extmetadata": {
                "Artist": { "value": "<b>Example &amp; Studio</b>" },
                "LicenseShortName": { "value": "CC BY-SA 4.0" }
              }
            }]
          },
          {
            "pageid": 11,
            "title": "File:Portrait.jpg",
            "imageinfo": [{
              "size": 1000000,
              "width": 1800,
              "height": 2600,
              "url": "https://upload.wikimedia.org/example/Portrait.jpg",
              "descriptionurl": "https://commons.wikimedia.org/wiki/File:Portrait.jpg",
              "thumburl": "https://upload.wikimedia.org/example/thumb/Portrait.jpg"
            }]
          },
          {
            "pageid": 12,
            "title": "File:Too_Large.jpg",
            "imageinfo": [{
              "size": 70000000,
              "width": 8000,
              "height": 4500,
              "url": "https://upload.wikimedia.org/example/Too_Large.jpg",
              "descriptionurl": "https://commons.wikimedia.org/wiki/File:Too_Large.jpg",
              "thumburl": "https://upload.wikimedia.org/example/thumb/Too_Large.jpg"
            }]
          },
          {
            "pageid": 13,
            "title": "File:Animated.gif",
            "imageinfo": [{
              "size": 2000000,
              "width": 4000,
              "height": 2250,
              "url": "https://upload.wikimedia.org/example/Animated.gif",
              "descriptionurl": "https://commons.wikimedia.org/wiki/File:Animated.gif",
              "thumburl": "https://upload.wikimedia.org/example/thumb/Animated.jpg"
            }]
          }
        ]
      }
    }
    """#
    let results = try OnlineWallpaperService.parseSearchResponse(Data(fixture.utf8))
    guard results.count == 1 else { throw TestError("expected one suitable landscape") }
    let result = results[0]
    guard result.title == "Mountain Lake.jpg" else { throw TestError("title normalization failed") }
    guard result.artist == "Example & Studio" else { throw TestError("artist cleanup failed") }
    guard result.license == "CC BY-SA 4.0" else { throw TestError("license parsing failed") }
    guard result.resolution == "6000 × 3375" else { throw TestError("resolution failed") }

    var dictionaryObject = try JSONSerialization.jsonObject(with: Data(fixture.utf8)) as! [String: Any]
    var query = dictionaryObject["query"] as! [String: Any]
    let pages = query["pages"] as! [[String: Any]]
    query["pages"] = Dictionary(uniqueKeysWithValues: pages.map { (String($0["pageid"] as! Int), $0) })
    dictionaryObject["query"] = query
    let dictionaryResults = try OnlineWallpaperService.parseSearchResponse(
      JSONSerialization.data(withJSONObject: dictionaryObject)
    )
    guard dictionaryResults.count == 1 else { throw TestError("dictionary pages parsing failed") }

    let communityFixture = #"""
    {
      "schemaVersion": 1,
      "items": [
        {
          "id": 1000001,
          "title": "Community Rose",
          "originalURL": "https://github.com/user-attachments/assets/11111111-1111-1111-1111-111111111111",
          "thumbnailURL": "https://github.com/user-attachments/assets/11111111-1111-1111-1111-111111111111",
          "detailsURL": "https://github.com/iStig/Codex-Skin-Clinet/issues/123",
          "width": 2560,
          "height": 1440,
          "byteCount": 2400000,
          "artist": "Example Creator",
          "license": "CC BY 4.0",
          "fileExtension": "jpg"
        },
        {
          "id": 1000002,
          "title": "Untrusted Host",
          "originalURL": "https://example.com/image.jpg",
          "thumbnailURL": "https://example.com/thumb.jpg",
          "detailsURL": "https://github.com/iStig/Codex-Skin-Clinet/issues/124",
          "width": 2560,
          "height": 1440,
          "byteCount": 2400000,
          "artist": "Bad",
          "license": "CC0 1.0",
          "fileExtension": "jpg"
        },
        {
          "id": 1000003,
          "title": "Old Repository",
          "originalURL": "https://github.com/user-attachments/assets/22222222-2222-2222-2222-222222222222",
          "thumbnailURL": "https://github.com/user-attachments/assets/22222222-2222-2222-2222-222222222222",
          "detailsURL": "https://github.com/Fei-Away/Codex-Dream-Skin/issues/125",
          "width": 2560,
          "height": 1440,
          "byteCount": 2400000,
          "artist": "Old Source",
          "license": "CC0 1.0",
          "fileExtension": "jpg"
        }
      ]
    }
    """#
    let communityResults = try OnlineWallpaperService.parseCommunityResponse(Data(communityFixture.utf8))
    guard communityResults.count == 1 else { throw TestError("community trust filtering failed") }
    guard communityResults[0].provider == "Dream Skin Community" else {
      throw TestError("community provider metadata failed")
    }
    print("PASS: online/community parsing, metadata cleanup, trust, and suitability filters.")
  }
}

private struct TestError: Error {
  let message: String
  init(_ message: String) { self.message = message }
}
