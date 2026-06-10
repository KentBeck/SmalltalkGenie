Class {
	#name : 'GenieProtocolTest',
	#superclass : 'TestCase',
	#category : 'Genie-Tests',
	#package : 'Genie',
	#tag : 'Tests'
}

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
GenieProtocolTest >> testToolsListIncludesCoreTools [
	| resp names |
	resp := GenieServer new handleMcpMessage: { 'method' -> 'tools/list'. 'id' -> 2 } asDictionary.
	names := ((resp at: 'result') at: 'tools') collect: [ :t | t at: 'name' ].
	self assert: (names includes: 'eval').
	self assert: (names includes: 'define_class').
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
