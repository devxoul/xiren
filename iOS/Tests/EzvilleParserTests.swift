import Foundation
import Testing
@testable import Xiren

struct EzvilleParserTests {
  @Test func encodePasswordXorsAndZeroPads() throws {
    #expect(try EzvilleParser.encodePassword("ab", checkstring: "AAAA") == "20234141")
  }

  @Test func encodePasswordRejectsPasswordLongerThanCheckstring() {
    #expect(throws: EzvilleError.self) { try EzvilleParser.encodePassword("abcde", checkstring: "abc") }
  }

  @Test func checkstringIsFoundInEitherAttributeOrder() {
    #expect(EzvilleParser.checkstring(in: #"<input type="hidden" id="checkstring" value="XyZ123">"#) == "XyZ123")
    #expect(EzvilleParser.checkstring(in: #"<input value='abc' id='checkstring'>"#) == "abc")
    #expect(EzvilleParser.checkstring(in: "<html></html>") == nil)
  }

  @Test func doorsAreParsedFromLobbyPanel() {
    let html = """
    <ul>
      <li class="item" onclick="selectDoor(0, '101', '9001', 'lobby')"><span>101동 로비층 1&#126;2라인</span></li>
      <li onclick="selectDoor(1,101,9011,'lobby')"><p>101동 지하 1층 1~2라인</p> <span>(lobby)</span> <button>선택</button></li>
      <li onclick="selectDoor(2, '101', '1501', 'unit')">세대현관</li>
      <li onclick="selectDoor(3, '101', '9001', 'lobby')">duplicate</li>
    </ul>
    """
    let doors = EzvilleParser.doors(in: html)
    #expect(doors == [
      Door(dong: "101", ho: "9001", name: "101동 로비층 1~2라인"),
      Door(dong: "101", ho: "9011", name: "101동 지하 1층 1~2라인"),
    ])
    #expect(doors[0].shortName == "로비층 1~2라인")
  }

  @Test func controlResultHandlesJsonAndHtml() {
    #expect(EzvilleParser.controlResult(Data(#"{"result":true,"msg":"열림"}"#.utf8)) == ControlResult(ok: true, message: "열림"))
    #expect(EzvilleParser.controlResult(Data(#"{"result":"false"}"#.utf8)) == ControlResult(ok: false, message: nil))
    #expect(EzvilleParser.controlResult(Data("<html>login</html>".utf8)) == nil)
  }

  @Test func lobbyDoorCodesAreIn9000Range() {
    #expect(EzvilleParser.isLobbyDoorCode("9023"))
    #expect(!EzvilleParser.isLobbyDoorCode("1501"))
    #expect(!EzvilleParser.isLobbyDoorCode("18000"))
  }
}
