// Use this file to write queries to test your data connector
let
    result = UiPathConnector.ReadEntities("accountname","tenantname","clientid")
    //result = UiPathConnector.Credential()
in
    result