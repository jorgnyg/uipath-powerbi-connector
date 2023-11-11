section UiPathConnector;

baseUri = "https://cloud.uipath.com/";
authorizeUri = baseUri & "/identity_/connect/authorize";
tokenUri = baseUri & "/identity_/connect/token";
redirect_uri = "https://oauth.powerbi.com/views/oauthredirect.html";  
windowWidth = 1200;
windowHeight = 1000;
pageLimit = 1000;

[DataSource.Kind="UiPathConnectorRead", Publish="UiPathConnector.Publish"]
shared UiPathConnector.ReadEntities = Value.ReplaceType(ReadEntities, UiPathConnectorReadTypes);

[DataSource.Kind="UiPathConnectorRead"]
shared UiPathConnector.Credential = (accountName as text, tenantName as text, client_id as text, datapoint as text, scope as text) => 
   Extension.CurrentCredential(true);

// Data Service UI publishing description
UiPathConnector.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://docs.uipath.com/data-service/docs",
    SourceImage = UiPathConnector.Icons,
    SourceTypeImage = UiPathConnector.Icons
];

UiPathConnector.Icons = [
    Icon16 = { Extension.Contents("Icon16.png"), Extension.Contents("Icon20.png"), Extension.Contents("Icon24.png"), Extension.Contents("Icon32.png") },
    Icon32 = { Extension.Contents("Icon32.png"), Extension.Contents("Icon40.png"), Extension.Contents("Icon48.png"), Extension.Contents("Icon64.png") }
];

// Data Service Read Kind description
UiPathConnectorRead = [
    Authentication = [
        OAuth = [
            StartLogin = StartLogin,
            FinishLogin = FinishLogin,
            Refresh	= Refresh
        ]
    ],
    Label = Extension.LoadString("DataSourceLabel"),
    TestConnection = (dataSourcePath) => 
        let 
            json = Json.Document(dataSourcePath),
            accountName = json[accountName],
            tenantName = json[tenantName],
            client_id = json[client_id],
            datapoint = json[datapoint],
            scope = json[scope]
        in
            {"UiPathConnector.ReadEntities", accountName, tenantName, client_id, datapoint, scope}
];

ReadEntities = (accountName as text, tenantName as text, client_id as text, datapoint as text, scope as text) as table =>
    let
        schemaUrl = baseUri & "/" & accountName & "/" & tenantName & "/orchestrator_/odata/" & datapoint,
        body = Json.Document(Web.Contents(schemaUrl, [Headers=[Accept="application/json"]])),
        values = body[value],
        finalTable = Table.FromList(values, Splitter.SplitByNothing(), null, null, ExtraValues.Error)
    in
        finalTable;

UiPathConnectorReadTypes = type function (
    accountName as (type text meta [
        Documentation.FieldCaption = Extension.LoadString("AccountNameCaption"),
        Documentation.FieldDescription = Extension.LoadString("AccountNameDescription"),
        Documentation.SampleValues = {"uipathTelecom"}
    ]),
    tenantName as (type text meta [
        Documentation.FieldCaption = Extension.LoadString("TenantNameCaption"),
        Documentation.FieldDescription = Extension.LoadString("TenantNameDescription"),
        Documentation.SampleValues = {"Default"}
    ]),
    client_id as (type text meta [
        Documentation.FieldCaption = Extension.LoadString("AppIDCaption"),
        Documentation.FieldDescription = Extension.LoadString("AppIDDescription"),
        Documentation.SampleValues = {"8bc59efd-d5c0-49de-a5bc-501a38d56e5c"}
    ]),
    datapoint as (type text meta [
        Documentation.FieldCaption = Extension.LoadString("DatapointCaption"),
        Documentation.FieldDescription = Extension.LoadString("DatapointDescription"),
        Documentation.SampleValues = {"Folders"}
    ]),
    scope as (type text meta [
        Documentation.FieldCaption = Extension.LoadString("ScopeCaption"),
        Documentation.FieldDescription = Extension.LoadString("ScopeDescription"),
        Documentation.SampleValues = {"OR.Folders.Read"}
    ]))
    as table meta [
        Documentation.Name = Extension.LoadString("ReadTypesName"),
        Documentation.LongDescription = Extension.LoadString("ReadTypesDescription")];

//Authentication functions
StartLogin = (dataSourcePath, state, display) =>
    let
        json = Json.Document(dataSourcePath),
        client_id = json[client_id],
        scope = json[scope],
        CodeVerifier = Text.NewGuid() & Text.NewGuid(),
        AuthorizeUrl = authorizeUri & "?" & Uri.BuildQueryString([
            client_id = client_id,
            state = state,
            scope = scope & " offline_access",
            redirect_uri = redirect_uri,
            code_challenge = CreateSha256Hash(CodeVerifier),
            code_challenge_method = "S256",
            response_type = "code"])
    in
        [
            LoginUri = AuthorizeUrl,
            CallbackUri = redirect_uri,
            WindowHeight = windowHeight,
            WindowWidth = windowWidth,
            Context = CodeVerifier
        ];

FinishLogin = (clientApplication, dataSourcePath, context, callbackUri, state) =>
    let
        queryParams = Uri.Parts(callbackUri)[Query],
        code = queryParams[code]
    in
        TokenMethod(dataSourcePath, "authorization_code", "code", code, context);

Refresh = (dataSourcePath, refreshToken) =>
     TokenMethod(dataSourcePath, "refresh_token", "refresh_token", refreshToken);

// grantType:  Maps to the "grant_type" query parameter.
// tokenField: The name of the query parameter to pass in the code.
// code:       Is the actual code (authorization_code or refresh_token) to send to the service.
TokenMethod = (dataSourcePath, grantType, tokenField, code, optional verifier) =>
    let
        json = Json.Document(dataSourcePath),
        client_id = json[client_id],
        CodeVerifier = if (verifier <> null) then [code_verifier = verifier] else [],
        queryString = CodeVerifier & [
            grant_type = grantType,
            client_id = client_id,
            redirect_uri = redirect_uri
        ],
        queryWithCode = Record.AddField(queryString, tokenField, code),
        tokenResponse = Web.Contents(tokenUri, [
            Content = Text.ToBinary(Uri.BuildQueryString(queryWithCode)),
            Headers = [
                #"Content-type" = "application/x-www-form-urlencoded",
                #"Accept" = "application/json"
            ]
        ]),
        body = Json.Document(tokenResponse),
        result = if (Record.HasFields(body, {"error", "error_description"})) then 
                    error Error.Record(body[error], body[error_description], body)
                 else
                    body
    in
        result;

//Common Code
CreateSha256Hash = (codeVerifier) =>
    let
        hash = Crypto.CreateHash(CryptoAlgorithm.SHA256, Text.ToBinary(codeVerifier)),
        base64Text = Binary.ToText(hash, BinaryEncoding.Base64),
        base64TextTrimmed = Text.TrimEnd(base64Text, "="),
        base64Url = Text.Replace(Text.Replace(base64TextTrimmed, "+", "-"), "/", "_")
    in
        base64Url;



