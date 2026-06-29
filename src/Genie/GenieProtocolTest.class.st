Class {
	#name : 'GenieProtocolTest',
	#superclass : 'TestCase',
	#category : 'Genie-Tests',
	#package : 'Genie',
	#tag : 'Tests'
}

{ #category : 'tests' }
GenieProtocolTest >> testAuthTokenOptInEnforcement [
	| open secured |
	open := GenieServer new.
	self assert: (open headersAuthorized: Dictionary new).
	secured := GenieServer new.
	secured settings at: #authToken put: 'sekret'.
	self deny: (secured headersAuthorized: Dictionary new).
	self deny: (secured headersAuthorized: { 'Authorization' -> 'Bearer nope' } asDictionary).
	self assert: (secured headersAuthorized: { 'Authorization' -> 'Bearer sekret' } asDictionary)
]

{ #category : 'tests' }
GenieProtocolTest >> testBindingDefaultsToLoopback [
	| server allIfaces |
	server := GenieServer new.
	self assert: server bindingInterface equals: '127.0.0.1'.
	self assert: server bindingAddress notNil.
	allIfaces := GenieServer new.
	allIfaces settings at: #bindingInterface put: ''.
	self assert: allIfaces bindingAddress isNil
]

{ #category : 'tests' }
GenieProtocolTest >> testDangerousToolGateBlocksWhenDisabled [
	| server blocked allowed |
	server := GenieServer new.
	server settings at: #allowDangerousTools put: false.
	blocked := server mcpToolsCall: { 'name' -> 'eval'. 'arguments' -> { 'code' -> '1 + 1' } asDictionary } asDictionary id: 1.
	self assert: (blocked includesKey: 'error').
	server settings at: #allowDangerousTools put: true.
	allowed := server mcpToolsCall: { 'name' -> 'eval'. 'arguments' -> { 'code' -> '1 + 1' } asDictionary } asDictionary id: 1.
	self assert: (allowed includesKey: 'result')
]

{ #category : 'tests' }
GenieProtocolTest >> testGetSettingsRedactsAuthToken [
	| server result |
	server := GenieServer new.
	server settings at: #authToken put: 'topsecret'.
	result := (server handleGetSettings: nil) at: 'result'.
	self assert: (result at: #authToken) equals: '***set***'.
	self deny: ((result at: #authToken) includesSubstring: 'topsecret')
]

{ #category : 'tests' }
GenieProtocolTest >> testInitializeReturnsProtocolAndCapabilities [
	| resp result |
	resp := GenieServer new handleMcpMessage: {
		'method' -> 'initialize'. 'id' -> 1.
		'params' -> { 'protocolVersion' -> '2025-11-25' } asDictionary } asDictionary.
	result := resp at: 'result'.
	self assert: (result at: 'protocolVersion') equals: '2025-11-25'.
	self assert: ((result at: 'capabilities') includesKey: 'tools').
	self assert: ((result at: 'serverInfo') at: 'name') equals: 'genie'
]

{ #category : 'tests' }
GenieProtocolTest >> testNotificationReturnsNil [
	self assert: (GenieServer new handleMcpMessage:
		{ 'method' -> 'notifications/initialized' } asDictionary) isNil
]

{ #category : 'tests' }
GenieProtocolTest >> testOriginCheckAllowsLocalRejectsRemote [
	| server |
	server := GenieServer new.
	self assert: (server originAllowed: Dictionary new).
	self assert: (server originAllowed: { 'Origin' -> 'http://localhost:8087' } asDictionary).
	self assert: (server originAllowed: { 'Origin' -> 'http://127.0.0.1:8087' } asDictionary).
	self deny: (server originAllowed: { 'Origin' -> 'http://evil.example.com' } asDictionary)
]

{ #category : 'tests' }
GenieProtocolTest >> testRenameMethodToolSchemaHasRequiredFields [

	| resp renameMethodTool schema required properties |
	resp := GenieServer new handleMcpMessage: {
			        ('method' -> 'tools/list').
			        ('id' -> 2) } asDictionary.
	renameMethodTool := ((resp at: 'result') at: 'tools') detect: [ :t |
		                    (t at: 'name') = 'rename_method' ].
	schema := renameMethodTool at: 'inputSchema'.
	required := schema at: 'required'.
	properties := schema at: 'properties'.
	self assert: (schema at: 'type') equals: 'object'.
	self assert: (required includes: 'class_name').
	self assert: (required includes: 'method_name').
	self assert: (required includes: 'new_method_name').
	self
		assert: ((properties at: 'permutation') at: 'type')
		equals: 'array'
]

{ #category : 'tests' }
GenieProtocolTest >> testToolsCallEvalReturnsTextContent [
	| resp result content |
	resp := GenieServer new handleMcpMessage: {
		'method' -> 'tools/call'. 'id' -> 3.
		'params' -> { 'name' -> 'eval'. 'arguments' -> { 'code' -> '6 * 7' } asDictionary } asDictionary } asDictionary.
	result := resp at: 'result'.
	content := result at: 'content'.
	self assert: content notEmpty.
	self assert: ((content first) at: 'type') equals: 'text'.
	self assert: (((content first) at: 'text') includesSubstring: '42').
	self deny: (result at: 'isError')
]

{ #category : 'tests' }
GenieProtocolTest >> testToolsCallRenameMethodUpdatesSenders [

	| cleanup server request resp result content fooClass barClass |
	cleanup := [
		           #( 'GenieFixtureFoo' 'GenieFixtureBar' 'GenieFixtureRenamed' )
			           do: [ :nm |
					           (Smalltalk classNamed: nm) ifNotNil: [ :c |
						           c removeFromSystem ].
					           Undeclared removeKey: nm asSymbol ifAbsent: [ nil ] ].
		           (GenieServer new packageOrganizer
			            packageNamed: 'Genie-Fixtures'
			            ifAbsent: [ nil ]) ifNotNil: [ :p | p removeFromSystem ] ].
	cleanup value.
	[
		(Smalltalk includesKey: #Author) ifTrue: [
			(Smalltalk classNamed: #Author) fullName: 'Genie' ].
		server := GenieServer new.
		request := [ :dict | Wish new setArguments: dict asDictionary ].
		server handleDefineClass: (request value: {
					 ('class_name' -> 'GenieFixtureFoo').
					 ('superclass_name' -> 'Object').
					 ('fields' -> '').
					 ('package_name' -> 'Genie-Fixtures') }).
		server handleDefineClass: (request value: {
					 ('class_name' -> 'GenieFixtureBar').
					 ('superclass_name' -> 'Object').
					 ('fields' -> '').
					 ('package_name' -> 'Genie-Fixtures') }).
		server handleDefineMethod: (request value: {
					 ('class_name' -> 'GenieFixtureFoo').
					 ('source' -> 'oldValue
	^ 42').
					 ('protocol' -> 'accessing') }).
		server handleDefineMethod: (request value: {
					 ('class_name' -> 'GenieFixtureBar').
					 ('source' -> 'useFoo
	^ GenieFixtureFoo new oldValue').
					 ('protocol' -> 'accessing') }).
		resp := server handleMcpMessage: {
				        ('method' -> 'tools/call').
				        ('id' -> 5).
				        ('params' -> {
					         ('name' -> 'rename_method').
					         ('arguments' -> {
						          ('class_name' -> 'GenieFixtureFoo').
						          ('method_name' -> 'oldValue').
						          ('new_method_name' -> 'renamedValue') } asDictionary) }
					         asDictionary) } asDictionary.
		result := resp at: 'result'.
		content := result at: 'content'.
		self deny: (result at: 'isError').
		self assert:
			((content first at: 'text') includesSubstring: 'renamedValue').
		fooClass := Smalltalk classNamed: 'GenieFixtureFoo'.
		barClass := Smalltalk classNamed: 'GenieFixtureBar'.
		self deny: (fooClass includesSelector: 'oldValue' asSymbol).
		self assert: (fooClass includesSelector: 'renamedValue' asSymbol).
		self assert:
			((barClass >> #useFoo) sourceCode includesSubstring: 'renamedValue') ]
		ensure: [ cleanup value ]
]

{ #category : 'tests' }
GenieProtocolTest >> testToolsListIncludesCoreTools [

	| resp names |
	resp := GenieServer new handleMcpMessage: {
			        ('method' -> 'tools/list').
			        ('id' -> 2) } asDictionary.
	names := ((resp at: 'result') at: 'tools') collect: [ :t |
		         t at: 'name' ].
	self assert: (names includes: 'eval').
	self assert: (names includes: 'define_class').
	self assert: (names includes: 'rename_method').
	self assert: (names includes: 'run_test')
]

{ #category : 'tests' }
GenieProtocolTest >> testToolsListSchemaHasRequiredFields [
	| resp evalTool |
	resp := GenieServer new handleMcpMessage: { 'method' -> 'tools/list'. 'id' -> 2 } asDictionary.
	evalTool := ((resp at: 'result') at: 'tools') detect: [ :t | (t at: 'name') = 'eval' ].
	self assert: ((evalTool at: 'inputSchema') at: 'type') equals: 'object'.
	self assert: (((evalTool at: 'inputSchema') at: 'required') includes: 'code')
]

{ #category : 'tests' }
GenieProtocolTest >> testUnknownMethodReturnsJsonRpcError [
	| resp |
	resp := GenieServer new handleMcpMessage: { 'method' -> 'frobnicate'. 'id' -> 9 } asDictionary.
	self assert: (resp includesKey: 'error').
	self assert: ((resp at: 'error') at: 'code') equals: -32601
]

{ #category : 'tests' }
GenieProtocolTest >> testUnknownToolReturnsError [
	| resp |
	resp := GenieServer new handleMcpMessage: {
		'method' -> 'tools/call'. 'id' -> 4.
		'params' -> { 'name' -> 'nope'. 'arguments' -> Dictionary new } asDictionary } asDictionary.
	self assert: (resp includesKey: 'error')
]
