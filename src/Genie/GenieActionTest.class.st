Class {
	#name : 'GenieActionTest',
	#superclass : 'TestCase',
	#category : 'Genie-Tests',
	#package : 'Genie',
	#tag : 'Tests'
}

{ #category : 'helpers' }
GenieActionTest >> intervalFor: substring inSourceOf: selector in: aClass [

	| source start |
	source := aClass sourceCodeAt: selector.
	start := source findString: substring.
	self assert: start > 0.
	^ start to: start + substring size - 1
]

{ #category : 'helpers' }
GenieActionTest >> invoke: aSelector with: aDictionary [
	^ GenieServer new perform: aSelector with: (Wish new setArguments: aDictionary)
]

{ #category : 'support' }
GenieActionTest >> invokeVariableRefactoring: toolName with: aDictionary [

	| arguments |
	arguments := aDictionary copy.
	arguments at: 'tool_name' put: toolName.
	^ self invoke: #handleVariableRefactoring: with: arguments
]

{ #category : 'running' }
GenieActionTest >> setUp [
	super setUp.
	(Smalltalk includesKey: #Author) ifTrue: [ (Smalltalk classNamed: #Author) fullName: 'Genie' ]
]

{ #category : 'running' }
GenieActionTest >> tearDown [

	#( 'GenieFixtureFoo' 'GenieFixtureBar' 'GenieFixtureRenamed'
	   'GenieVarFixture' 'GenieVarFixtureChild' 'GenieVarFixtureSibling'
	   'GenieAccessorFixture' 'GenieTempFixture' ) do: [ :nm |
			(Smalltalk classNamed: nm) ifNotNil: [ :c | c removeFromSystem ].
			Undeclared removeKey: nm asSymbol ifAbsent: [ nil ] ].
	(GenieServer new packageOrganizer
		 packageNamed: 'Genie-Fixtures'
		 ifAbsent: [ nil ]) ifNotNil: [ :p | p removeFromSystem ].
	super tearDown
]

{ #category : 'tests' }
GenieActionTest >> testApplyThenGetSettings [
	| s apply get |
	s := GenieServer new.
	apply := s handleApplySettings: (Wish new setArguments: { 'settings' -> { 'stack_size' -> 42 } asDictionary } asDictionary).
	self assert: (apply at: 'success').
	get := s handleGetSettings: nil.
	self assert: ((get at: 'result') at: #stackSize) equals: 42
]

{ #category : 'tests' }
GenieActionTest >> testDefineClassActionCreatesClass [
	| result cls |
	result := self invoke: #handleDefineClass: with: {
		'class_name' -> 'GenieFixtureFoo'.
		'superclass_name' -> 'Object'.
		'fields' -> 'a b'.
		'package_name' -> 'Genie-Fixtures' } asDictionary.
	self assert: (result at: 'success').
	self assert: (result at: 'result') equals: 'GenieFixtureFoo'.
	cls := Smalltalk classNamed: 'GenieFixtureFoo'.
	self assert: cls notNil.
	self assert: (cls instVarNames collect: [ :e | e asString ]) asArray equals: #('a' 'b')
]

{ #category : 'tests' }
GenieActionTest >> testDefineClassUnknownSuperclassReportsError [
	| result |
	result := self invoke: #handleDefineClass: with: {
		'class_name' -> 'GenieFixtureBar'.
		'superclass_name' -> 'NoSuchSuperXYZ'.
		'fields' -> ''.
		'package_name' -> 'Genie-Fixtures' } asDictionary.
	self deny: (result at: 'success').
	self assert: (result includesKey: 'error')
]

{ #category : 'tests' }
GenieActionTest >> testDefineMethodActionCompilesMethod [
	| defResult cls |
	self invoke: #handleDefineClass: with: {
		'class_name' -> 'GenieFixtureFoo'. 'superclass_name' -> 'Object'.
		'fields' -> ''. 'package_name' -> 'Genie-Fixtures' } asDictionary.
	defResult := self invoke: #handleDefineMethod: with: {
		'class_name' -> 'GenieFixtureFoo'.
		'source' -> 'double: x
	^ x * 2'.
		'protocol' -> 'arithmetic' } asDictionary.
	self assert: (defResult at: 'success').
	self assert: (defResult at: 'result') equals: 'double:'.
	cls := Smalltalk classNamed: 'GenieFixtureFoo'.
	self assert: (cls includesSelector: #double:).
	self assert: (cls new double: 21) equals: 42
]

{ #category : 'tests' }
GenieActionTest >> testDefineMethodFormatsSourceOnCompile [
	| src |
	self invoke: #handleDefineClass: with: { 'class_name' -> 'GenieFixtureFoo'. 'superclass_name' -> 'Object'. 'fields' -> ''. 'package_name' -> 'Genie-Fixtures' } asDictionary.
	self invoke: #handleDefineMethod: with: { 'class_name' -> 'GenieFixtureFoo'. 'source' -> 'fmtProbe ^1+2'. 'protocol' -> 'tests' } asDictionary.
	src := ((Smalltalk classNamed: 'GenieFixtureFoo') >> #fmtProbe) sourceCode.
	self assert: (src includesSubstring: '^ 1 + 2').
	self deny: (src includesSubstring: '^1+2')
]

{ #category : 'tests' }
GenieActionTest >> testEvalActionEvaluatesCode [
	| result |
	result := self invoke: #handleEval: with: { 'code' -> '3 + 4 factorial' } asDictionary.
	self assert: (result at: 'success').
	self assert: (result at: 'result') equals: 27
]

{ #category : 'tests' }
GenieActionTest >> testExportPackageWritesTonelPropertiesMarker [
	| dir result propsFile |
	dir := '/tmp/genie-export-test' asFileReference.
	dir exists ifTrue: [ dir ensureDeleteAll ].
	dir ensureCreateDirectory.
	[ result := self invoke: #handleExportPackage: with: { 'package_name' -> 'BaselineOfGenie'. 'path' -> dir fullName } asDictionary.
	  self assert: (result at: 'success').
	  propsFile := dir / '.properties'.
	  self assert: propsFile exists.
	  self assert: (propsFile contents includesSubstring: 'tonel') ]
		ensure: [ dir exists ifTrue: [ dir ensureDeleteAll ] ]
]

{ #category : 'tests' }
GenieActionTest >> testGetSettingsReturnsStackSize [
	| result |
	result := GenieServer new handleGetSettings: nil.
	self assert: (result at: 'success').
	self assert: ((result at: 'result') at: #stackSize) equals: 100
]

{ #category : 'tests' }
GenieActionTest >> testListClassesActionListsPackageClasses [
	| result |
	result := self invoke: #handleListClasses: with: { 'package_name' -> 'Genie' } asDictionary.
	self assert: (result at: 'success').
	self assert: ((result at: 'result') anySatisfy: [ :n | n asString = 'GenieServer' ])
]

{ #category : 'tests' }
GenieActionTest >> testRemoveClassActionRemovesClass [
	| result |
	self invoke: #handleDefineClass: with: {
		'class_name' -> 'GenieFixtureBar'.
		'superclass_name' -> 'Object'.
		'fields' -> ''.
		'package_name' -> 'Genie-Fixtures' } asDictionary.
	self assert: (Smalltalk includesKey: #GenieFixtureBar).
	result := self invoke: #handleRemoveClass: with: {
		'class_name' -> 'GenieFixtureBar' } asDictionary.
	self assert: (result at: 'success').
	self deny: (Smalltalk includesKey: #GenieFixtureBar)
]

{ #category : 'tests' }
GenieActionTest >> testRemoveMethodActionRemovesMethod [
	| result cls |
	self invoke: #handleDefineClass: with: {
		'class_name' -> 'GenieFixtureFoo'. 'superclass_name' -> 'Object'.
		'fields' -> ''. 'package_name' -> 'Genie-Fixtures' } asDictionary.
	self invoke: #handleDefineMethod: with: {
		'class_name' -> 'GenieFixtureFoo'. 'source' -> 'ping
	^ 1'. 'protocol' -> 'tests' } asDictionary.
	cls := Smalltalk classNamed: 'GenieFixtureFoo'.
	self assert: (cls includesSelector: #ping).
	result := self invoke: #handleRemoveMethod: with: {
		'class_name' -> 'GenieFixtureFoo'. 'method_name' -> 'ping' } asDictionary.
	self assert: (result at: 'success').
	self deny: (cls includesSelector: #ping)
]

{ #category : 'tests' }
GenieActionTest >> testRenameClassRenamesAndUpdatesReferences [
	| result |
	self invoke: #handleDefineClass: with: { 'class_name' -> 'GenieFixtureFoo'. 'superclass_name' -> 'Object'. 'fields' -> ''. 'package_name' -> 'Genie-Fixtures' } asDictionary.
	self invoke: #handleDefineClass: with: { 'class_name' -> 'GenieFixtureBar'. 'superclass_name' -> 'Object'. 'fields' -> ''. 'package_name' -> 'Genie-Fixtures' } asDictionary.
	self invoke: #handleDefineMethod: with: { 'class_name' -> 'GenieFixtureBar'. 'source' -> 'makeFoo
	^ GenieFixtureFoo new'. 'protocol' -> 'accessing' } asDictionary.
	result := self invoke: #handleRenameClass: with: { 'class_name' -> 'GenieFixtureFoo'. 'new_class_name' -> 'GenieFixtureRenamed' } asDictionary.
	self assert: (result at: 'success').
	self deny: (Smalltalk includesKey: 'GenieFixtureFoo' asSymbol).
	self assert: (Smalltalk includesKey: 'GenieFixtureRenamed' asSymbol).
	self assert: (((Smalltalk classNamed: 'GenieFixtureBar') >> #makeFoo) sourceCode includesSubstring: 'GenieFixtureRenamed')
]

{ #category : 'tests' }
GenieActionTest >> testRenameMethodActionRenamesAndUpdatesReferences [

	| result fooClass barClass |
	self invoke: #handleDefineClass: with: {
			('class_name' -> 'GenieFixtureFoo').
			('superclass_name' -> 'Object').
			('fields' -> '').
			('package_name' -> 'Genie-Fixtures') } asDictionary.
	self invoke: #handleDefineClass: with: {
			('class_name' -> 'GenieFixtureBar').
			('superclass_name' -> 'Object').
			('fields' -> '').
			('package_name' -> 'Genie-Fixtures') } asDictionary.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieFixtureFoo').
			('source' -> 'oldValue
	^ 42').
			('protocol' -> 'accessing') } asDictionary.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieFixtureBar').
			('source' -> 'useFoo
	^ GenieFixtureFoo new oldValue').
			('protocol' -> 'accessing') } asDictionary.
	result := self invoke: #handleRenameMethod: with: {
			          ('class_name' -> 'GenieFixtureFoo').
			          ('method_name' -> 'oldValue').
			          ('new_method_name' -> 'renamedValue') } asDictionary.
	self assert: (result at: 'success').
	fooClass := Smalltalk classNamed: 'GenieFixtureFoo'.
	barClass := Smalltalk classNamed: 'GenieFixtureBar'.
	self deny: (fooClass includesSelector: 'oldValue' asSymbol).
	self assert: (fooClass includesSelector: 'renamedValue' asSymbol).
	self assert:
		((barClass >> #useFoo) sourceCode includesSubstring: 'renamedValue').
	self assert: barClass new useFoo equals: 42
]

{ #category : 'tests' }
GenieActionTest >> testRunTestActionReportsStructuredResults [
	| result inner |
	self invoke: #handleDefineClass: with: {
		'class_name' -> 'GenieFixtureBar'. 'superclass_name' -> 'TestCase'.
		'fields' -> ''. 'package_name' -> 'Genie-Fixtures' } asDictionary.
	self invoke: #handleDefineMethod: with: {
		'class_name' -> 'GenieFixtureBar'. 'source' -> 'testPasses
	self assert: true'. 'protocol' -> 'tests' } asDictionary.
	self invoke: #handleDefineMethod: with: {
		'class_name' -> 'GenieFixtureBar'. 'source' -> 'testFails
	self assert: false'. 'protocol' -> 'tests' } asDictionary.
	result := self invoke: #handleRunTest: with: { 'class_name' -> 'GenieFixtureBar' } asDictionary.
	self assert: (result at: 'success').
	inner := result at: 'result'.
	self assert: (inner at: 'total') equals: 2.
	self assert: (inner at: 'passed') equals: 1.
	self assert: (inner at: 'failed') equals: 1
]

{ #category : 'tests' }
GenieActionTest >> testSaveImageGateBlocksWhenTestsFail [
	| result inner |
	self invoke: #handleDefineClass: with: { 'class_name' -> 'GenieFixtureBar'. 'superclass_name' -> 'TestCase'. 'fields' -> ''. 'package_name' -> 'Genie-Fixtures' } asDictionary.
	self invoke: #handleDefineMethod: with: { 'class_name' -> 'GenieFixtureBar'. 'source' -> 'testAlwaysFails
	self assert: false'. 'protocol' -> 'tests' } asDictionary.
	result := self invoke: #handleSaveImage: with: { 'test_class' -> 'GenieFixtureBar' } asDictionary.
	self assert: (result at: 'success').
	inner := result at: 'result'.
	self deny: (inner at: 'saved').
	self assert: ((inner at: 'tests') at: 'failed') >= 1
]

{ #category : 'tests' }
GenieActionTest >> testSettingsIsSelfContained [
	self assert: GenieServer new settings class name asString equals: 'GenieSettings'
]

{ #category : 'tests' }
GenieActionTest >> testVariableRefactoringToolsAddRenameRemoveInstanceAndClassVariables [

	| targetClass names result |
	self invoke: #handleDefineClass: with: {
			('class_name' -> 'GenieVarFixture').
			('superclass_name' -> 'Object').
			('fields' -> '').
			('package_name' -> 'Genie-Fixtures') } asDictionary.
	targetClass := Smalltalk classNamed: 'GenieVarFixture'.
	result := self
		          invokeVariableRefactoring: 'add_instance_variable'
		          with: {
				          ('class_name' -> 'GenieVarFixture').
				          ('variable_name' -> 'foo') } asDictionary.
	self assert: (result at: 'success').
	self assert:
		((targetClass instVarNames collect: #asString) includes: 'foo').
	result := self
		          invokeVariableRefactoring: 'rename_instance_variable'
		          with: {
				          ('class_name' -> 'GenieVarFixture').
				          ('variable_name' -> 'foo').
				          ('new_variable_name' -> 'bar') } asDictionary.
	self assert: (result at: 'success').
	names := targetClass instVarNames collect: #asString.
	self deny: (names includes: 'foo').
	self assert: (names includes: 'bar').
	result := self
		          invokeVariableRefactoring: 'remove_instance_variable'
		          with: {
				          ('class_name' -> 'GenieVarFixture').
				          ('variable_name' -> 'bar') } asDictionary.
	self assert: (result at: 'success').
	self deny:
		((targetClass instVarNames collect: #asString) includes: 'bar').
	result := self
		          invokeVariableRefactoring: 'add_class_variable'
		          with: {
				          ('class_name' -> 'GenieVarFixture').
				          ('variable_name' -> 'Foo') } asDictionary.
	self assert: (result at: 'success').
	self assert:
		((targetClass classVarNames collect: #asString) includes: 'Foo').
	result := self
		          invokeVariableRefactoring: 'rename_class_variable'
		          with: {
				          ('class_name' -> 'GenieVarFixture').
				          ('variable_name' -> 'Foo').
				          ('new_variable_name' -> 'Bar') } asDictionary.
	self assert: (result at: 'success').
	names := targetClass classVarNames collect: #asString.
	self deny: (names includes: 'Foo').
	self assert: (names includes: 'Bar').
	result := self
		          invokeVariableRefactoring: 'remove_shared_variable'
		          with: {
				          ('class_name' -> 'GenieVarFixture').
				          ('variable_name' -> 'Bar') } asDictionary.
	self assert: (result at: 'success').
	self deny:
		((targetClass classVarNames collect: #asString) includes: 'Bar')
]

{ #category : 'tests' }
GenieActionTest >> testVariableRefactoringToolsGenerateAccessors [

	| targetClass result source |
	self invoke: #handleDefineClass: with: {
			('class_name' -> 'GenieAccessorFixture').
			('superclass_name' -> 'Object').
			('fields' -> 'thing cached other').
			('package_name' -> 'Genie-Fixtures') } asDictionary.
	targetClass := Smalltalk classNamed: 'GenieAccessorFixture'.
	result := self
		          invokeVariableRefactoring: 'generate_variable_accessor'
		          with: {
				          ('class_name' -> 'GenieAccessorFixture').
				          ('variable_name' -> 'thing') } asDictionary.
	self assert: (result at: 'success').
	self assert: (targetClass includesSelector: #thing).
	self assert: (targetClass includesSelector: #thing:).
	result := self
		          invokeVariableRefactoring: 'generate_variable_accessors'
		          with: {
				          ('class_name' -> 'GenieAccessorFixture').
				          ('variable_names' -> #( 'other' )) } asDictionary.
	self assert: (result at: 'success').
	self assert: (targetClass includesSelector: #other).
	self assert: (targetClass includesSelector: #other:).
	result := self
		          invokeVariableRefactoring:
		          'generate_lazy_variable_accessor'
		          with: {
				          ('class_name' -> 'GenieAccessorFixture').
				          ('variable_name' -> 'cached').
				          ('default_value' -> '42') } asDictionary.
	self assert: (result at: 'success').
	self assert: (targetClass includesSelector: #cached).
	source := (targetClass >> #cached) sourceCode.
	self assert: (source includesSubstring: '42')
]

{ #category : 'tests' }
GenieActionTest >> testVariableRefactoringToolsMergeAndProtectInstanceVariables [

	| cls result source instVarNames |
	self invoke: #handleDefineClass: with: {
			('class_name' -> 'GenieVarFixture').
			('superclass_name' -> 'Object').
			('fields' -> 'left right secret').
			('package_name' -> 'Genie-Fixtures') } asDictionary.
	cls := Smalltalk classNamed: 'GenieVarFixture'.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieVarFixture').
			('source' -> 'combined
	left := 1.
	right := left + 2.
	^ right').
			('protocol' -> 'tests') } asDictionary.
	result := self
		          invokeVariableRefactoring: 'merge_instance_variable'
		          with: {
				          ('class_name' -> 'GenieVarFixture').
				          ('variable_name' -> 'left').
				          ('target_variable_name' -> 'right') } asDictionary.
	self assert: (result at: 'success').
	instVarNames := cls instVarNames collect: #asString.
	self deny: (instVarNames includes: 'left').
	self assert: (instVarNames includes: 'right').
	source := cls sourceCodeAt: #combined.
	self deny: (source includesSubstring: 'left').
	self assert: (source includesSubstring: 'right := 1').
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieVarFixture').
			('source' -> 'secret
	^ secret').
			('protocol' -> 'accessing') } asDictionary.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieVarFixture').
			('source' -> 'secret: anObject
	secret := anObject').
			('protocol' -> 'accessing') } asDictionary.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieVarFixture').
			('source' -> 'readSecret
	^ self secret').
			('protocol' -> 'tests') } asDictionary.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieVarFixture').
			('source'
			 -> 'writeSecret: anObject
	self secret: anObject.
	^ secret').
			('protocol' -> 'tests') } asDictionary.
	result := self
		          invokeVariableRefactoring: 'protect_instance_variable'
		          with: {
				          ('class_name' -> 'GenieVarFixture').
				          ('variable_name' -> 'secret') } asDictionary.
	self assert: (result at: 'success').
	self assert:
		((cls sourceCodeAt: #readSecret) includesSubstring: '^ secret').
	self deny:
		((cls sourceCodeAt: #readSecret) includesSubstring: 'self secret').
	self assert: ((cls sourceCodeAt: #writeSecret:) includesSubstring:
			 'secret := anObject')
]

{ #category : 'tests' }
GenieActionTest >> testVariableRefactoringToolsPullUpAndPushDownVariables [

	| parent child result parentInst childInst parentClassVars childClassVars |
	self invoke: #handleDefineClass: with: {
			('class_name' -> 'GenieVarFixture').
			('superclass_name' -> 'Object').
			('fields' -> 'pushed').
			('package_name' -> 'Genie-Fixtures') } asDictionary.
	self invoke: #handleDefineClass: with: {
			('class_name' -> 'GenieVarFixtureChild').
			('superclass_name' -> 'GenieVarFixture').
			('fields' -> 'pulled').
			('package_name' -> 'Genie-Fixtures') } asDictionary.
	parent := Smalltalk classNamed: 'GenieVarFixture'.
	child := Smalltalk classNamed: 'GenieVarFixtureChild'.
	result := self
		          invokeVariableRefactoring: 'pull_up_instance_variable'
		          with: {
				          ('class_name' -> 'GenieVarFixtureChild').
				          ('variable_name' -> 'pulled') } asDictionary.
	self assert: (result at: 'success').
	self assert:
		((parent instVarNames collect: #asString) includes: 'pulled').
	result := self
		          invokeVariableRefactoring: 'push_down_instance_variable'
		          with: {
				          ('class_name' -> 'GenieVarFixture').
				          ('variable_name' -> 'pushed') } asDictionary.
	self assert: (result at: 'success').
	parentInst := parent instVarNames collect: #asString.
	childInst := child instVarNames collect: #asString.
	self deny: (parentInst includes: 'pushed').
	self assert: (childInst includes: 'pushed').
	result := self
		          invokeVariableRefactoring: 'add_class_variable'
		          with: {
				          ('class_name' -> 'GenieVarFixtureChild').
				          ('variable_name' -> 'PulledClassVar') } asDictionary.
	self assert: (result at: 'success').
	result := self
		          invokeVariableRefactoring: 'pull_up_class_variable'
		          with: {
				          ('class_name' -> 'GenieVarFixtureChild').
				          ('variable_name' -> 'PulledClassVar') } asDictionary.
	self assert: (result at: 'success').
	parentClassVars := parent classVarNames collect: #asString.
	self assert: (parentClassVars includes: 'PulledClassVar').
	result := self
		          invokeVariableRefactoring: 'add_class_variable'
		          with: {
				          ('class_name' -> 'GenieVarFixture').
				          ('variable_name' -> 'PushedClassVar') } asDictionary.
	self assert: (result at: 'success').
	result := self invoke: #handleDefineMethod: with: {
			          ('class_name' -> 'GenieVarFixtureChild').
			          ('source' -> 'pushedClassVarValue
	^ PushedClassVar').
			          ('protocol' -> 'accessing') } asDictionary.
	self assert: (result at: 'success').
	result := self
		          invokeVariableRefactoring: 'push_down_class_variable'
		          with: {
				          ('class_name' -> 'GenieVarFixture').
				          ('variable_name' -> 'PushedClassVar') } asDictionary.
	self assert: (result at: 'success').
	parentClassVars := parent classVarNames collect: #asString.
	childClassVars := child classVarNames collect: #asString.
	self deny: (parentClassVars includes: 'PushedClassVar').
	self assert: (childClassVars includes: 'PushedClassVar')
]

{ #category : 'tests' }
GenieActionTest >> testVariableRefactoringToolsTemporaryRefactorings [

	| cls result interval source start beforeReturn afterReturn instVarNames |
	self invoke: #handleDefineClass: with: {
			('class_name' -> 'GenieTempFixture').
			('superclass_name' -> 'Object').
			('fields' -> '').
			('package_name' -> 'Genie-Fixtures') } asDictionary.
	cls := Smalltalk classNamed: 'GenieTempFixture'.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieTempFixture').
			('source' -> 'renameTemp
	| count |
	count := 1.
	^ count + count').
			('protocol' -> 'tests') } asDictionary.
	interval := self intervalFor: 'count' inSourceOf: #renameTemp in: cls.
	result := self
		          invokeVariableRefactoring: 'rename_argument_or_temporary'
		          with: {
				          ('class_name' -> 'GenieTempFixture').
				          ('method_name' -> 'renameTemp').
				          ('new_variable_name' -> 'total').
				          ('start' -> interval first).
				          ('stop' -> interval last) } asDictionary.
	self assert: (result at: 'success').
	source := cls sourceCodeAt: #renameTemp.
	self assert: (source includesSubstring: 'total := 1').
	self deny: (source includesSubstring: 'count').
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieTempFixture').
			('source' -> 'promoteTemp
	| cache |
	cache := 5.
	^ cache').
			('protocol' -> 'tests') } asDictionary.
	result := self
		          invokeVariableRefactoring:
		          'temporary_to_instance_variable'
		          with: {
				          ('class_name' -> 'GenieTempFixture').
				          ('method_name' -> 'promoteTemp').
				          ('variable_name' -> 'cache') } asDictionary.
	self assert: (result at: 'success').
	instVarNames := cls instVarNames collect: #asString.
	self assert: (instVarNames includes: 'cache').
	self deny:
		((cls sourceCodeAt: #promoteTemp) includesSubstring: '| cache |').
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieTempFixture').
			('source' -> 'extractTemp
	^ 3 + 4').
			('protocol' -> 'tests') } asDictionary.
	interval := self
		            intervalFor: '3 + 4'
		            inSourceOf: #extractTemp
		            in: cls.
	result := self
		          invokeVariableRefactoring: 'extract_temporary'
		          with: {
				          ('class_name' -> 'GenieTempFixture').
				          ('method_name' -> 'extractTemp').
				          ('variable_name' -> 'sum').
				          ('start' -> interval first).
				          ('stop' -> interval last) } asDictionary.
	self assert: (result at: 'success').
	source := cls sourceCodeAt: #extractTemp.
	self assert: (source includesSubstring: '| sum |').
	self assert: (source includesSubstring: 'sum := 3 + 4').
	self assert: (source includesSubstring: '^ sum').
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieTempFixture').
			('source' -> 'inlineTemp
	| sum |
	sum := 3 + 4.
	^ sum').
			('protocol' -> 'tests') } asDictionary.
	interval := self
		            intervalFor: 'sum := 3 + 4'
		            inSourceOf: #inlineTemp
		            in: cls.
	result := self invokeVariableRefactoring: 'inline_temporary' with: {
			          ('class_name' -> 'GenieTempFixture').
			          ('method_name' -> 'inlineTemp').
			          ('start' -> interval first).
			          ('stop' -> interval last) } asDictionary.
	self assert: (result at: 'success').
	source := cls sourceCodeAt: #inlineTemp.
	self assert: (source includesSubstring: '^ 3 + 4').
	self deny: (source includesSubstring: 'sum').
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieTempFixture').
			('source' -> 'cleanTemp
	| used spare |
	used := 1.
	^ used').
			('protocol' -> 'tests') } asDictionary.
	result := self
		          invokeVariableRefactoring: 'remove_unused_temporary'
		          with: {
				          ('class_name' -> 'GenieTempFixture').
				          ('method_name' -> 'cleanTemp') } asDictionary.
	self assert: (result at: 'success').
	source := cls sourceCodeAt: #cleanTemp.
	self assert: (source includesSubstring: '| used |').
	self deny: (source includesSubstring: 'spare').
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieTempFixture').
			('source'
			 ->
			 'moveTemp
	| temp |
	^ #(1 2) collect: [ :each |
		temp := each printString.
		temp ]').
			('protocol' -> 'tests') } asDictionary.
	source := cls sourceCodeAt: #moveTemp.
	start := (source findString: '| temp |') + 2.
	interval := start to: start + 'temp' size - 1.
	result := self
		          invokeVariableRefactoring:
		          'move_variable_definition_to_smallest_scope'
		          with: {
				          ('class_name' -> 'GenieTempFixture').
				          ('method_name' -> 'moveTemp').
				          ('start' -> interval first).
				          ('stop' -> interval last) } asDictionary.
	self assert: (result at: 'success').
	source := cls sourceCodeAt: #moveTemp.
	start := source findString: '^'.
	beforeReturn := source copyFrom: 1 to: start - 1.
	afterReturn := source copyFrom: start to: source size.
	self deny: (beforeReturn includesSubstring: '| temp |').
	self assert: (afterReturn includesSubstring: '| temp |')
]
