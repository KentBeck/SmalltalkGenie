Class {
	#name : #GenieActionTest,
	#superclass : #TestCase,
	#category : #'Genie-Tests'
}

{ #category : #helpers }
GenieActionTest >> invoke: aSelector with: aDictionary [
	^ GenieServer new perform: aSelector with: (Wish new setArguments: aDictionary)
]

{ #category : #running }
GenieActionTest >> setUp [
	super setUp.
	Author fullName: 'KentBeck'
]

{ #category : #running }
GenieActionTest >> tearDown [
	#('GenieFixtureFoo' 'GenieFixtureBar' 'GenieFixtureRenamed') do: [ :nm |
		(Smalltalk classNamed: nm) ifNotNil: [ :c | c removeFromSystem ] ].
	(RPackageOrganizer default packageNamed: 'Genie-Fixtures' ifAbsent: [ nil ])
		ifNotNil: [ :p | p removeFromSystem ].
	super tearDown
]

{ #category : #tests }
GenieActionTest >> testApplyThenGetSettings [
	| s apply get |
	s := GenieServer new.
	apply := s handleApplySettings: (Wish new setArguments: { 'settings' -> { 'stack_size' -> 42 } asDictionary } asDictionary).
	self assert: (apply at: 'success').
	get := s handleGetSettings: nil.
	self assert: ((get at: 'result') at: #stackSize) equals: 42
]

{ #category : #tests }
GenieActionTest >> testDefineClassActionCreatesClass [
	| result cls |
	result := self invoke: #handleDefineClass: with: {
		'name' -> 'GenieFixtureFoo'.
		'superclass' -> 'Object'.
		'fields' -> 'a b'.
		'package' -> 'Genie-Fixtures' } asDictionary.
	self assert: (result at: 'success').
	self assert: (result at: 'result') equals: 'GenieFixtureFoo'.
	cls := Smalltalk classNamed: 'GenieFixtureFoo'.
	self assert: cls notNil.
	self assert: (cls instVarNames collect: [ :e | e asString ]) asArray equals: #('a' 'b')
]

{ #category : #tests }
GenieActionTest >> testDefineClassUnknownSuperclassReportsError [
	| result |
	result := self invoke: #handleDefineClass: with: {
		'name' -> 'GenieFixtureBar'.
		'superclass' -> 'NoSuchSuperXYZ'.
		'fields' -> ''.
		'package' -> 'Genie-Fixtures' } asDictionary.
	self deny: (result at: 'success').
	self assert: (result includesKey: 'error')
]

{ #category : #tests }
GenieActionTest >> testDefineMethodActionCompilesMethod [
	| defResult cls |
	self invoke: #handleDefineClass: with: {
		'name' -> 'GenieFixtureFoo'. 'superclass' -> 'Object'.
		'fields' -> ''. 'package' -> 'Genie-Fixtures' } asDictionary.
	defResult := self invoke: #handleDefineMethod: with: {
		'class' -> 'GenieFixtureFoo'.
		'source' -> 'double: x
	^ x * 2'.
		'protocol' -> 'arithmetic' } asDictionary.
	self assert: (defResult at: 'success').
	self assert: (defResult at: 'result') equals: 'double:'.
	cls := Smalltalk classNamed: 'GenieFixtureFoo'.
	self assert: (cls includesSelector: #double:).
	self assert: (cls new double: 21) equals: 42
]

{ #category : #tests }
GenieActionTest >> testEvalActionEvaluatesCode [
	| result |
	result := self invoke: #handleEval: with: { 'code' -> '3 + 4 factorial' } asDictionary.
	self assert: (result at: 'success').
	self assert: (result at: 'result') equals: 27
]

{ #category : #tests }
GenieActionTest >> testGetSettingsReturnsStackSize [
	| result |
	result := GenieServer new handleGetSettings: nil.
	self assert: (result at: 'success').
	self assert: ((result at: 'result') at: #stackSize) equals: 100
]

{ #category : #tests }
GenieActionTest >> testRemoveClassActionRemovesClass [
	| result |
	self invoke: #handleDefineClass: with: {
		'name' -> 'GenieFixtureBar'.
		'superclass' -> 'Object'.
		'fields' -> ''.
		'package' -> 'Genie-Fixtures' } asDictionary.
	self assert: (Smalltalk includesKey: #GenieFixtureBar).
	result := self invoke: #handleRemoveClass: with: {
		'name' -> 'GenieFixtureBar' } asDictionary.
	self assert: (result at: 'success').
	self deny: (Smalltalk includesKey: #GenieFixtureBar)
]

{ #category : #tests }
GenieActionTest >> testRemoveMethodActionRemovesMethod [
	| result cls |
	self invoke: #handleDefineClass: with: {
		'name' -> 'GenieFixtureFoo'. 'superclass' -> 'Object'.
		'fields' -> ''. 'package' -> 'Genie-Fixtures' } asDictionary.
	self invoke: #handleDefineMethod: with: {
		'class' -> 'GenieFixtureFoo'. 'source' -> 'ping
	^ 1'. 'protocol' -> 'tests' } asDictionary.
	cls := Smalltalk classNamed: 'GenieFixtureFoo'.
	self assert: (cls includesSelector: #ping).
	result := self invoke: #handleRemoveMethod: with: {
		'class' -> 'GenieFixtureFoo'. 'selector' -> 'ping' } asDictionary.
	self assert: (result at: 'success').
	self deny: (cls includesSelector: #ping)
]

{ #category : #tests }
GenieActionTest >> testRenameClassRenamesAndUpdatesReferences [
	| result |
	self invoke: #handleDefineClass: with: { 'name' -> 'GenieFixtureFoo'. 'superclass' -> 'Object'. 'fields' -> ''. 'package' -> 'Genie-Fixtures' } asDictionary.
	self invoke: #handleDefineClass: with: { 'name' -> 'GenieFixtureBar'. 'superclass' -> 'Object'. 'fields' -> ''. 'package' -> 'Genie-Fixtures' } asDictionary.
	self invoke: #handleDefineMethod: with: { 'class' -> 'GenieFixtureBar'. 'source' -> 'makeFoo
	^ GenieFixtureFoo new'. 'protocol' -> 'accessing' } asDictionary.
	result := self invoke: #handleRenameClass: with: { 'old_name' -> 'GenieFixtureFoo'. 'new_name' -> 'GenieFixtureRenamed' } asDictionary.
	self assert: (result at: 'success').
	self deny: (Smalltalk includesKey: 'GenieFixtureFoo' asSymbol).
	self assert: (Smalltalk includesKey: 'GenieFixtureRenamed' asSymbol).
	self assert: (((Smalltalk classNamed: 'GenieFixtureBar') >> #makeFoo) sourceCode includesSubstring: 'GenieFixtureRenamed')
]

{ #category : #tests }
GenieActionTest >> testRunTestActionReportsStructuredResults [
	| result inner |
	self invoke: #handleDefineClass: with: {
		'name' -> 'GenieFixtureBar'. 'superclass' -> 'TestCase'.
		'fields' -> ''. 'package' -> 'Genie-Fixtures' } asDictionary.
	self invoke: #handleDefineMethod: with: {
		'class' -> 'GenieFixtureBar'. 'source' -> 'testPasses
	self assert: true'. 'protocol' -> 'tests' } asDictionary.
	self invoke: #handleDefineMethod: with: {
		'class' -> 'GenieFixtureBar'. 'source' -> 'testFails
	self assert: false'. 'protocol' -> 'tests' } asDictionary.
	result := self invoke: #handleRunTest: with: { 'class_name' -> 'GenieFixtureBar' } asDictionary.
	self assert: (result at: 'success').
	inner := result at: 'result'.
	self assert: (inner at: 'total') equals: 2.
	self assert: (inner at: 'passed') equals: 1.
	self assert: (inner at: 'failed') equals: 1
]

{ #category : #tests }
GenieActionTest >> testSaveImageGateBlocksWhenTestsFail [
	| result inner |
	self invoke: #handleDefineClass: with: { 'name' -> 'GenieFixtureBar'. 'superclass' -> 'TestCase'. 'fields' -> ''. 'package' -> 'Genie-Fixtures' } asDictionary.
	self invoke: #handleDefineMethod: with: { 'class' -> 'GenieFixtureBar'. 'source' -> 'testAlwaysFails
	self assert: false'. 'protocol' -> 'tests' } asDictionary.
	result := self invoke: #handleSaveImage: with: { 'test_class' -> 'GenieFixtureBar' } asDictionary.
	self assert: (result at: 'success').
	inner := result at: 'result'.
	self deny: (inner at: 'saved').
	self assert: ((inner at: 'tests') at: 'failed') >= 1
]

{ #category : #tests }
GenieActionTest >> testSettingsIsSelfContained [
	self assert: GenieServer new settings class name asString equals: 'GenieSettings'
]
