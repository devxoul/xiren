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

  @Test func inputValueReadsHiddenFields() {
    let html = #"<input type="hidden" id="seq" name="seq" value="42" /><input type="hidden" id="act" name="act" value="auth">"#
    #expect(EzvilleParser.inputValue(id: "seq", in: html) == "42")
    #expect(EzvilleParser.inputValue(id: "act", in: html) == "auth")
    #expect(EzvilleParser.inputValue(id: "missing", in: html) == nil)
  }

  @Test func passwordResetQueryMatchesFindPasswordForm() {
    let form = PasswordResetForm(dong: " 101 ", ho: "1501", email: "user@example.com", code: "123456", newPassword: "Secret123!")
    #expect(form.query().map(\.0) == ["seq", "act", "hh_dong", "hh_ho", "email", "auth_num", "devicetoken"])
    #expect(form.query().map(\.1) == ["", "auth", "101", "1501", "user@example.com", "123456", "token"])
    let save = form.query(includingPassword: true, seq: "7")
    #expect(save.first! == ("seq", "7"))
    #expect(save.suffix(2).map(\.0) == ["new_pwd", "new_pwd_check"])
    #expect(save.suffix(2).allSatisfy { $0.1 == "Secret123!" })
  }

  @Test func resetCodeResultSucceedsOnlyOnZero() {
    #expect(EzvilleParser.resetCodeResult(Data(#"{"result":"0"}"#.utf8)) == ControlResult(ok: true, message: nil))
    #expect(EzvilleParser.resetCodeResult(Data(#"{"result":0}"#.utf8))?.ok == true)
    #expect(EzvilleParser.resetCodeResult(Data(#"{"result":"1","msg":"인증번호 오류"}"#.utf8)) == ControlResult(ok: false, message: "인증번호 오류"))
    #expect(EzvilleParser.resetCodeResult(Data("<html></html>".utf8)) == nil)
  }

  @Test func passwordSaveResultUsesJavaScriptTruthiness() {
    #expect(EzvilleParser.passwordSaveResult(Data(#"{"result":true}"#.utf8))?.ok == true)
    #expect(EzvilleParser.passwordSaveResult(Data(#"{"result":"0"}"#.utf8))?.ok == true)
    #expect(EzvilleParser.passwordSaveResult(Data(#"{"result":false,"msg":"no"}"#.utf8)) == ControlResult(ok: false, message: "no"))
    #expect(EzvilleParser.passwordSaveResult(Data(#"{"result":""}"#.utf8))?.ok == false)
  }

  @Test func newPasswordRules() {
    #expect(EzvilleParser.isAcceptedNewPassword("Abcdef1!"))
    #expect(EzvilleParser.isAcceptedNewPassword("abcdefgh12"))
    #expect(!EzvilleParser.isAcceptedNewPassword("abcdefg12"))
    #expect(!EzvilleParser.isAcceptedNewPassword("Abcde1!"))
    #expect(!EzvilleParser.isAcceptedNewPassword("abcdefghijklmnop"))
    #expect(!EzvilleParser.isAcceptedNewPassword("Abcdefghij1!Abcdefghij"))
  }

  @Test func customDoorRequiresDongAndLobbyCode() {
    #expect(EzvilleParser.customDoor(dong: " 101 ", ho: "9001", name: "") == Door(dong: "101", ho: "9001", name: "101동 9001"))
    #expect(EzvilleParser.customDoor(dong: "101", ho: "9011", name: " 친구네 ")?.name == "친구네")
    #expect(EzvilleParser.customDoor(dong: "101", ho: "1501", name: "") == nil)
    #expect(EzvilleParser.customDoor(dong: "", ho: "9001", name: "") == nil)
  }

  @Test func mergedDoorsKeepPanelFirstAndDropDuplicates() {
    let panel = [Door(dong: "102", ho: "9001", name: "102동 로비층 1~2라인")]
    let custom = [Door(dong: "102", ho: "9001", name: "dup"), Door(dong: "101", ho: "9001", name: "101동 9001")]
    #expect(Preferences.merging(panel, custom).map(\.id) == ["102-9001", "101-9001"])
  }

  @Test func floorRowsGroupByDongThenFloor() {
    let door = { (dong: String, ho: String) in Door(dong: dong, ho: ho, name: "") }
    let doors = [door("102", "9013"), door("102", "9001"), door("102", "9021"), door("101", "9001"), door("102", "9011"), door("102", "9003")]
    #expect(Door.floorRows(doors).map { $0.map(\.id) } == [
      ["102-9001", "102-9003"],
      ["102-9011", "102-9013"],
      ["102-9021"],
      ["101-9001"],
    ])
  }

  @MainActor @Test func hiddenDoorsLeaveDoorScreenButNotShortcuts() {
    let saved = (Preferences.doors, Preferences.customDoors, Preferences.hiddenDoorIDs)
    defer { (Preferences.doors, Preferences.customDoors, Preferences.hiddenDoorIDs) = saved }
    let lobby = Door(dong: "101", ho: "9001", name: "101동 9001")
    let basement = Door(dong: "101", ho: "9011", name: "101동 9011")
    Preferences.doors = [lobby, basement]
    Preferences.customDoors = []
    Preferences.hiddenDoorIDs = []

    let model = AppModel()
    model.setHidden(lobby, true)
    #expect(model.visibleDoors.map(\.id) == ["101-9011"])
    #expect(Preferences.allDoors.map(\.id) == ["101-9001", "101-9011"])
    #expect(AppModel().visibleDoors.map(\.id) == ["101-9011"])

    model.setHidden(lobby, false)
    #expect(model.visibleDoors.map(\.id) == ["101-9001", "101-9011"])
    #expect(Preferences.hiddenDoorIDs.isEmpty)
  }

  @Test func lobbyDoorCodesAreIn9000Range() {
    #expect(EzvilleParser.isLobbyDoorCode("9023"))
    #expect(!EzvilleParser.isLobbyDoorCode("1501"))
    #expect(!EzvilleParser.isLobbyDoorCode("18000"))
  }
}
