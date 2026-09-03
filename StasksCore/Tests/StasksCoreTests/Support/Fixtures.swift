import Foundation

enum Fixtures {
    static let reactionsList = """
    {"ok":true,"items":[
      {"type":"message","channel":"C1","message":{"type":"message","user":"UANA","text":"Can someone review the PR?\\nThanks","ts":"1788300000.000100","reactions":[{"name":"eyes","users":["UME"],"count":1}],"permalink":"https://soci.slack.com/archives/C1/p1788300000000100"}},
      {"type":"message","channel":"C1","message":{"type":"message","user":"UBOB","text":"Old one","ts":"1788200000.000200","reactions":[{"name":"eyes","users":["UME","UBOB"],"count":2},{"name":"white_check_mark","users":["UME"],"count":1}],"permalink":"https://x/2"}},
      {"type":"message","channel":"C2","message":{"type":"message","user":"UBOB","text":"Not mine","ts":"1788300000.000300","thread_ts":"1788299000.000000","reactions":[{"name":"eyes","users":["UBOB"],"count":1}],"permalink":"https://x/3"}},
      {"type":"file","file":{"id":"F1"}}
    ],"response_metadata":{"next_cursor":""}}
    """

    static let authTest = #"{"ok":true,"url":"https://soci.slack.com/","team":"SOCi","user":"luciano","team_id":"T1","user_id":"UME"}"#
    static let apiError = #"{"ok":false,"error":"invalid_auth"}"#
    static let channelInfo = #"{"ok":true,"channel":{"id":"C1","name":"eng-backend","is_im":false,"is_mpim":false}}"#
    static let dmInfo = #"{"ok":true,"channel":{"id":"D1","is_im":true,"user":"UANA"}}"#
    static let userInfo = #"{"ok":true,"user":{"id":"UANA","name":"ana","real_name":"Ana Souza","profile":{"display_name":"Ana"}}}"#
    static let replies = #"{"ok":true,"messages":[{"user":"UBOB","text":"root","ts":"1.0"},{"user":"UANA","text":"reply","ts":"2.0"}]}"#
}
