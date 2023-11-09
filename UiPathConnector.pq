section UiPathConnector;

baseUri = "https://cloud.uipath.com/";
authorizeUri = baseUri & "/identity_/connect/authorize";
tokenUri = baseUri & "/identity_/connect/token";
// Create app instead, set correct redirect url (same as below) and the needed scopes.
scope = "OR.Folders.Read OR.Monitoring offline_access"; // supply scope dynamically?
redirect_uri = "https://oauth.powerbi.com/views/oauthredirect.html";  
windowWidth = 1200;
windowHeight = 1000;
pageLimit = 1000;

[DataSource.Kind="UiPathConnectorRead", Publish="UiPathConnector.Publish"]
shared UiPathConnector.ReadEntities = Value.ReplaceType(ReadEntities, UiPathConnectorReadTypes);

[DataSource.Kind="UiPathConnectorRead"]
shared UiPathConnector.Credential = (accountName as text, tenantName as text, client_id as text) => 
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
            client_id = json[client_id]
        in
            {"UiPathConnector.ReadEntities", accountName, tenantName, client_id}
];

ReadEntities = (accountName as text, tenantName as text, client_id as text) as table =>
    let
        schemaUrl = baseUri & "/" & accountName & "/" & tenantName & "/orchestrator_/odata/Alerts", // Set Datapoint based on user input
        body = Json.Document(Web.Contents(schemaUrl, [Headers=[Accept="application/json"]])),
        values = body[value],
        finalTable = Table.FromList(values, Splitter.SplitByNothing(), null, null, ExtraValues.Error)
    in
        finalTable;

GetEntities = (rawSchema as table) as table =>
    let
        expandDataServiceType = Table.ExpandRecordColumn(rawSchema, "Value", {"x-uipath-dataservice-type", "properties"}, {"DataserviceType", "properties"}),
        selectEntities = Table.SelectRows(expandDataServiceType, each [DataserviceType] = "entity"),
        expandFields = Table.AddColumn(selectEntities, "Fields", each Record.ToTable([properties])),
        entities = Table.RemoveColumns(expandFields, {"properties"})
    in
        entities;

GetChoiceSets = (rawSchema as table) as table =>
    let
        expandDataServiceType = Table.ExpandRecordColumn(rawSchema, "Value", {"x-uipath-dataservice-type", "enum", "x-enum-varnames"}, {"DataserviceType", "values", "names"}),
        choiceSets = Table.SelectRows(expandDataServiceType, each [DataserviceType] = "choiceset")
    in
        choiceSets;

CreateChoicesetNavTable = (choicesets as table) =>
    let
        addDataColumn = Table.AddColumn(choicesets, "Data", each Table.FromColumns({[values], [names]}, {"Id", "Name"})),
        addItemKind = Table.AddColumn(addDataColumn, "ItemKind", each "Table"),
        addItemName = Table.AddColumn(addItemKind, "ItemName", each "Table"),
        addIsLeaf = Table.AddColumn(addItemName, "IsLeaf", each true),
        removeFields = Table.RemoveColumns(addIsLeaf, {"names", "values"}),
        NavTable = Table.ToNavigationTable(removeFields, {"Name"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        NavTable;

CreateEntitiesNavTable = (accountName as text, tenantName as text, entitiesList as table) =>
    let
        addDataColumn = Table.AddColumn(entitiesList, "Data", each ReadEntityData(baseUri, accountName, tenantName, [Name], [Fields])),
        addItemKind = Table.AddColumn(addDataColumn, "ItemKind", each "Table"),
        addItemName = Table.AddColumn(addItemKind, "ItemName", each "Table"),
        addIsLeaf = Table.AddColumn(addItemName, "IsLeaf", each true),
        removeFields = Table.RemoveColumns(addIsLeaf, {"Fields"}),
        NavTable = Table.ToNavigationTable(removeFields, {"Name"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        NavTable;

ReadEntityData = (baseUri as text, accountName as text, tenantName as text, entityName as text, fields as table) as table =>
    let 
        url = baseUri & "/" & accountName & "/" & tenantName & "/dataservice_/api/EntityService/" & entityName & "/read?",
        data = ReadEntityDataAllPages(url, Table.ToList(Table.SelectColumns(fields, {"Name"}))),
        columnsWithType = GetTableSchema(fields),
        tableWithType = Table.TransformColumnTypes(data, Table.ToList(columnsWithType, (row) => {row{0}, row{3}})),
        table=Table.AddKey(tableWithType, {"Id"}, true)
    in
        table;

ReadEntityDataAllPages = (url as text, fields as list) as table =>
    Table.GenerateByPage((previous) => 
        let
            // if previous is null, then this is our first page of data
            start = if (previous = null) then 0 else Value.Metadata(previous)[Skip],
            totalRecordCount = if (previous = null) then 1 else Value.Metadata(previous)[TotalRecordCount],
            // if start is less than total record count, we still have records to fetch
            page = if (start < totalRecordCount) then ReadEntityDataPage(url, fields, start) else null
        in
            page
    );

ReadEntityDataPage = (url as text, fields as list, start as number) as table =>
    let
        response = Web.Contents(url & "&limit=" & Text.From(pageLimit) & "&start=" & Text.From(start), [Headers=[Accept="application/json"]]),        
        body = Json.Document(response),
        data = Table.FromRecords(body[value], fields, MissingField.UseNull),
        skip = start + Table.RowCount(data),
        totalRecordCount = Number.From(body[totalRecordCount])
    in
        data meta [Skip = skip, TotalRecordCount = totalRecordCount];

GetTableSchema = (fields as table)  =>
    let
        expandFields = Table.ExpandRecordColumn(fields, "Value", {"type", "format", "$ref"}, {"type", "format", "ref"}),
        fixDateTime = Table.ReplaceValue(expandFields, each if [format] = "date-time" then "string" else "", "date-time", Replacer.ReplaceValue, {"type"}),
        fixDate = Table.ReplaceValue(fixDateTime, each if [format] = "date" then "string" else "", "date", Replacer.ReplaceValue, {"type"}),
        fixNumber = Table.ReplaceValue(fixDate, each if [format] = "double" then "number" else "", "double", Replacer.ReplaceValue, {"type"}),
        fixRelations = Table.ReplaceValue(fixNumber, each if Text.Contains([ref],"components/schemas") then null else "", "string", Replacer.ReplaceValue, {"type"}),
        removeExtraColumns = Table.RemoveColumns (fixRelations, {"format", "ref"}),
        columnsWithType = Table.Join(removeExtraColumns, {"type"}, TypeMap, "DataServiceTypes")
    in
        columnsWithType;

UiPathConnectorReadTypes = type function (
    accountName as (type text meta [
        Documentation.FieldCaption = Extension.LoadString("AccountNameCaption"),
        Documentation.FieldDescription = Extension.LoadString("AccountNameDescription"),
        Documentation.SampleValues = {"uipathTelecom"}
    ]),
    tenantName as (type text meta [
        Documentation.FieldCaption = Extension.LoadString("TenantNameCaption"),
        Documentation.FieldDescription = Extension.LoadString("TenantNameDescription"),
        Documentation.SampleValues = {"finance"}
    ]),
    client_id as (type text meta [
        Documentation.FieldCaption = "App ID",
        Documentation.FieldDescription = "App ID generated from UiPath Portal",
        Documentation.SampleValues = {"8bc59efd-d5c0-49de-a5bc-501a38d56e5c"}
    ]))
    as table meta [
        Documentation.Name = Extension.LoadString("ReadTypesName"),
        Documentation.LongDescription = Extension.LoadString("ReadTypesDescription")];

//Authentication functions
StartLogin = (dataSourcePath, state, display) =>
    let
        json = Json.Document(dataSourcePath),
        client_id = json[client_id],
        CodeVerifier = Text.NewGuid() & Text.NewGuid(),
        AuthorizeUrl = authorizeUri & "?" & Uri.BuildQueryString([
            client_id = client_id,
            state = state,
            scope = scope,
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

TypeMap = #table(
    { "DataServiceTypes", "Type" }, 
    { 
        { "string", Text.Type },
        { "double", Decimal.Type },
        { "date", Date.Type },
        { "date-time", DateTimeZone.Type },
        { "boolean", Logical.Type },
        { "array", Any.Type }
    });

//Source - https://docs.microsoft.com/en-us/power-query/helperfunctions#navigation-tables
Table.ToNavigationTable = (
    table as table,
    keyColumns as list,
    nameColumn as text,
    dataColumn as text,
    itemKindColumn as text,
    itemNameColumn as text,
    isLeafColumn as text
) as table =>
    let
        tableType = Value.Type(table),
        newTableType = Type.AddTableKey(tableType, keyColumns, true) meta 
        [
            NavigationTable.NameColumn = nameColumn, 
            NavigationTable.DataColumn = dataColumn,
            NavigationTable.ItemKindColumn = itemKindColumn, 
            Preview.DelayColumn = itemNameColumn, 
            NavigationTable.IsLeafColumn = isLeafColumn
        ],
        navigationTable = Value.ReplaceType(table, newTableType)
    in
        navigationTable;

//Source - https://docs.microsoft.com/en-us/power-query/helperfunctions#tablegeneratebypage
Table.GenerateByPage = (getNextPage as function) as table =>
    let        
        listOfPages = List.Generate(
            () => getNextPage(null),            // get the first page of data
            (lastPage) => lastPage <> null,     // stop when the function returns null
            (lastPage) => getNextPage(lastPage) // pass the previous page to the next function call
        ),
        // concatenate the pages together
        tableOfPages = Table.FromList(listOfPages, Splitter.SplitByNothing(), {"Column1"}),
        firstRow = tableOfPages{0}?
    in
        // if we didn't get back any pages of data, return an empty table
        // otherwise set the table type based on the columns of the first page
        if (firstRow = null) then
            Table.FromRows({})
        else        
            Value.ReplaceType(
                Table.ExpandTableColumn(tableOfPages, "Column1", Table.ColumnNames(firstRow[Column1])),
                Value.Type(firstRow[Column1])
            );