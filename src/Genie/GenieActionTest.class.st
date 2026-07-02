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

{ #category : 'helpers' }
GenieActionTest >> invokeMcpTool: toolName with: aDictionary [

	| resp result content message |
	resp := GenieServer new handleMcpMessage: {
			        ('method' -> 'tools/call').
			        ('id' -> 100).
			        ('params' -> {
				         ('name' -> toolName).
				         ('arguments' -> aDictionary) } asDictionary) }
			        asDictionary.
	result := resp at: 'result'.
	content := result at: 'content'.
	message := content isEmpty
		           ifTrue: [ '' ]
		           ifFalse: [ content first at: 'text' ifAbsent: [ '' ] ].
	self
		deny: (result at: 'isError')
		description: toolName , ' returned MCP error: ' , message.
	^ NeoJSONReader fromString: message
]

{ #category : 'helpers' }
GenieActionTest >> invokeMethodRefactoring: toolName with: aDictionary [

	^ self invokeMcpTool: toolName with: aDictionary
]

{ #category : 'helpers' }
GenieActionTest >> invokeVariableRefactoring: toolName with: aDictionary [

	^ self invokeMcpTool: toolName with: aDictionary
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
	   'GenieAccessorFixture' 'GenieTempFixture' 'GenieMethodFixture'
	   'GenieMethodTarget' 'GenieMethodParent' 'GenieMethodChild'
	   'GenieMethodSibling' ) do: [ :nm |
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
GenieActionTest >> testMethodRefactoringToolsCreateAndSplitCascade [

	| cls result source start stop semicolon interval |
	self invoke: #handleDefineClass: with: {
			('class_name' -> 'GenieMethodFixture').
			('superclass_name' -> 'Object').
			('fields' -> '').
			('package_name' -> 'Genie-Fixtures') } asDictionary.
	cls := Smalltalk classNamed: 'GenieMethodFixture'.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodFixture').
			('source'
			 ->
			 'makeCascade
	| builder |
	builder := OrderedCollection new.
	builder add: 1.
	builder add: 2.
	^ builder').
			('protocol' -> 'tests') } asDictionary.
	source := cls sourceCodeAt: #makeCascade.
	start := source findString: 'builder add: 1'.
	self assert: start > 0.
	stop := source findString: 'builder add: 2' startingAt: start.
	self assert: stop > 0.
	stop := stop + 'builder add: 2' size - 1.
	result := self invokeMethodRefactoring: 'create_cascade' with: {
			          ('class_name' -> 'GenieMethodFixture').
			          ('method_name' -> 'makeCascade').
			          ('start' -> start).
			          ('stop' -> stop) } asDictionary.
	self assert: (result at: 'success').
	source := cls sourceCodeAt: #makeCascade.
	self assert: (source includesSubstring: ';').
	self assert: cls new makeCascade asArray equals: #( 1 2 ).
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodFixture').
			('source'
			 ->
			 'splitCascadeSource
	| a |
	a := Object new initialize; asString.
	^ a').
			('protocol' -> 'tests') } asDictionary.
	source := cls sourceCodeAt: #splitCascadeSource.
	semicolon := source findString: ';'.
	self assert: semicolon > 0.
	interval := semicolon to: semicolon + 1.
	result := self invokeMethodRefactoring: 'split_cascade' with: {
			          ('class_name' -> 'GenieMethodFixture').
			          ('method_name' -> 'splitCascadeSource').
			          ('start' -> interval first).
			          ('stop' -> interval last) } asDictionary.
	self assert: (result at: 'success').
	source := cls sourceCodeAt: #splitCascadeSource.
	self deny: (source includesSubstring: ';').
	self assert: (source includesSubstring: 'receiver := Object new').
	self assert: (source includesSubstring: 'receiver initialize').
	self assert: (source includesSubstring: 'a := receiver asString')
]

{ #category : 'tests' }
GenieActionTest >> testMethodRefactoringToolsExtractAndInline [

	| cls interval result source |
	self invoke: #handleDefineClass: with: {
			('class_name' -> 'GenieMethodFixture').
			('superclass_name' -> 'Object').
			('fields' -> '').
			('package_name' -> 'Genie-Fixtures') } asDictionary.
	cls := Smalltalk classNamed: 'GenieMethodFixture'.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodFixture').
			('source' -> 'computed
	^ 3 + 4').
			('protocol' -> 'tests') } asDictionary.
	interval := self intervalFor: '3 + 4' inSourceOf: #computed in: cls.
	result := self invokeMethodRefactoring: 'extract_method' with: {
			          ('class_name' -> 'GenieMethodFixture').
			          ('method_name' -> 'computed').
			          ('new_method_name' -> 'sum').
			          ('start' -> interval first).
			          ('stop' -> interval last) } asDictionary.
	self assert: (result at: 'success').
	self assert: (cls includesSelector: #sum).
	source := cls sourceCodeAt: #computed.
	self assert: (source includesSubstring: 'self sum').
	interval := self
		            intervalFor: 'self sum'
		            inSourceOf: #computed
		            in: cls.
	result := self invokeMethodRefactoring: 'inline_method' with: {
			          ('class_name' -> 'GenieMethodFixture').
			          ('method_name' -> 'computed').
			          ('start' -> interval first).
			          ('stop' -> interval last) } asDictionary.
	self assert: (result at: 'success').
	self assert:
		((cls sourceCodeAt: #computed) includesSubstring: '^ 3 + 4').
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodFixture').
			('source' -> 'answer
	^ 42').
			('protocol' -> 'tests') } asDictionary.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodFixture').
			('source' -> 'useAnswer
	^ self answer').
			('protocol' -> 'tests') } asDictionary.
	result := self invokeMethodRefactoring: 'inline_all_senders' with: {
			          ('class_name' -> 'GenieMethodFixture').
			          ('method_name' -> 'answer') } asDictionary.
	self assert: (result at: 'success').
	self assert:
		((cls sourceCodeAt: #useAnswer) includesSubstring: '^ 42')
]

{ #category : 'tests' }
GenieActionTest >> testMethodRefactoringToolsExtractMethodAndOccurrences [

	| cls interval result source firstOccurrence secondOccurrence |
	self invoke: #handleDefineClass: with: {
			('class_name' -> 'GenieMethodFixture').
			('superclass_name' -> 'Object').
			('fields' -> '').
			('package_name' -> 'Genie-Fixtures') } asDictionary.
	cls := Smalltalk classNamed: 'GenieMethodFixture'.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodFixture').
			('source' -> 'repeatedExpression
	^ (1 + 2) + (1 + 2)').
			('protocol' -> 'tests') } asDictionary.
	interval := self
		            intervalFor: '1 + 2'
		            inSourceOf: #repeatedExpression
		            in: cls.
	result := self
		          invokeMethodRefactoring: 'extract_method_and_occurrences'
		          with: {
				          ('class_name' -> 'GenieMethodFixture').
				          ('method_name' -> 'repeatedExpression').
				          ('new_method_name' -> 'smallSum').
				          ('start' -> interval first).
				          ('stop' -> interval last) } asDictionary.
	self assert: (result at: 'success').
	self assert: (cls includesSelector: #smallSum).
	source := cls sourceCodeAt: #repeatedExpression.
	firstOccurrence := source findString: 'self smallSum'.
	self assert: firstOccurrence > 0.
	secondOccurrence := source
		                    findString: 'self smallSum'
		                    startingAt: firstOccurrence + 1.
	self assert: secondOccurrence > 0
]

{ #category : 'tests' }
GenieActionTest >> testMethodRefactoringToolsExtractMethodToComponent [

	| fixture target interval result source |
	self invoke: #handleDefineClass: with: {
			('class_name' -> 'GenieMethodTarget').
			('superclass_name' -> 'Object').
			('fields' -> '').
			('package_name' -> 'Genie-Fixtures') } asDictionary.
	self invoke: #handleDefineClass: with: {
			('class_name' -> 'GenieMethodFixture').
			('superclass_name' -> 'Object').
			('fields' -> 'component').
			('package_name' -> 'Genie-Fixtures') } asDictionary.
	fixture := Smalltalk classNamed: 'GenieMethodFixture'.
	target := Smalltalk classNamed: 'GenieMethodTarget'.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodTarget').
			('source' -> 'value
	^ 5').
			('protocol' -> 'tests') } asDictionary.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodFixture').
			('source' -> 'component: anObject
	component := anObject').
			('protocol' -> 'tests') } asDictionary.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodFixture').
			('source' -> 'delegated
	^ component value + 1').
			('protocol' -> 'tests') } asDictionary.
	interval := self
		            intervalFor: 'component value + 1'
		            inSourceOf: #delegated
		            in: fixture.
	result := self
		          invokeMethodRefactoring: 'extract_method_to_component'
		          with: {
				          ('class_name' -> 'GenieMethodFixture').
				          ('method_name' -> 'delegated').
				          ('new_method_name' -> 'componentTotal').
				          ('variable_name' -> 'component').
				          ('variable_type_names' -> #( 'GenieMethodTarget' )).
				          ('start' -> interval first).
				          ('stop' -> interval last) } asDictionary.
	self assert: (result at: 'success').
	self assert: (target includesSelector: #componentTotal).
	source := fixture sourceCodeAt: #delegated.
	self assert: (source includesSubstring: 'component componentTotal').
	self assert: target new componentTotal equals: 6
]

{ #category : 'tests' }
GenieActionTest >> testMethodRefactoringToolsExtractSetupMethods [

	| cls otherClass interval result source |
	self invoke: #handleDefineClass: with: {
			('class_name' -> 'GenieMethodFixture').
			('superclass_name' -> 'TestCase').
			('fields' -> 'value').
			('package_name' -> 'Genie-Fixtures') } asDictionary.
	cls := Smalltalk classNamed: 'GenieMethodFixture'.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodFixture').
			('source'
			 ->
			 'testUsesValue
	value := OrderedCollection new.
	self assert: value isEmpty').
			('protocol' -> 'tests') } asDictionary.
	interval := self
		            intervalFor: 'value := OrderedCollection new'
		            inSourceOf: #testUsesValue
		            in: cls.
	result := self
		          invokeMethodRefactoring: 'extract_setup_method'
		          with: {
				          ('class_name' -> 'GenieMethodFixture').
				          ('method_name' -> 'testUsesValue').
				          ('start' -> interval first).
				          ('stop' -> interval last) } asDictionary.
	self assert: (result at: 'success').
	self assert: (cls includesSelector: #setUp).
	self assert: ((cls sourceCodeAt: #setUp) includesSubstring:
			 'value := OrderedCollection new').
	self deny: ((cls sourceCodeAt: #testUsesValue) includesSubstring:
			 'value := OrderedCollection new').
	self invoke: #handleDefineClass: with: {
			('class_name' -> 'GenieMethodTarget').
			('superclass_name' -> 'TestCase').
			('fields' -> 'value').
			('package_name' -> 'Genie-Fixtures') } asDictionary.
	otherClass := Smalltalk classNamed: 'GenieMethodTarget'.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodTarget').
			('source'
			 ->
			 'testOne
	value := OrderedCollection new.
	self assert: value isEmpty').
			('protocol' -> 'tests') } asDictionary.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodTarget').
			('source'
			 ->
			 'testTwo
	value := OrderedCollection new.
	self deny: value notEmpty').
			('protocol' -> 'tests') } asDictionary.
	interval := self
		            intervalFor: 'value := OrderedCollection new'
		            inSourceOf: #testOne
		            in: otherClass.
	result := self
		          invokeMethodRefactoring:
		          'extract_setup_method_and_occurrences'
		          with: {
				          ('class_name' -> 'GenieMethodTarget').
				          ('method_name' -> 'testOne').
				          ('start' -> interval first).
				          ('stop' -> interval last) } asDictionary.
	self assert: (result at: 'success').
	self assert: (otherClass includesSelector: #setUp).
	source := otherClass sourceCodeAt: #setUp.
	self assert:
		(source includesSubstring: 'value := OrderedCollection new').
	self deny: ((otherClass sourceCodeAt: #testOne) includesSubstring:
			 'value := OrderedCollection new').
	self deny: ((otherClass sourceCodeAt: #testTwo) includesSubstring:
			 'value := OrderedCollection new')
]

{ #category : 'tests' }
GenieActionTest >> testMethodRefactoringToolsMessageRewrites [

	| cls result source |
	self invoke: #handleDefineClass: with: {
			('class_name' -> 'GenieMethodFixture').
			('superclass_name' -> 'Object').
			('fields' -> '').
			('package_name' -> 'Genie-Fixtures') } asDictionary.
	cls := Smalltalk classNamed: 'GenieMethodFixture'.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodFixture').
			('source' -> 'oldName
	^ 11').
			('protocol' -> 'tests') } asDictionary.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodFixture').
			('source' -> 'useOldName
	^ self oldName').
			('protocol' -> 'tests') } asDictionary.
	result := self
		          invokeMethodRefactoring: 'change_method_signature'
		          with: {
				          ('class_name' -> 'GenieMethodFixture').
				          ('method_name' -> 'oldName').
				          ('new_method_name' -> 'newName') } asDictionary.
	self assert: (result at: 'success').
	self assert: (cls includesSelector: #newName).
	self assert:
		((cls sourceCodeAt: #useOldName) includesSubstring: 'self newName').
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodFixture').
			('source' -> 'oldThing
	^ 1').
			('protocol' -> 'tests') } asDictionary.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodFixture').
			('source' -> 'newThing
	^ 2').
			('protocol' -> 'tests') } asDictionary.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodFixture').
			('source' -> 'useThing
	^ self oldThing').
			('protocol' -> 'tests') } asDictionary.
	result := self
		          invokeMethodRefactoring: 'replace_message_send'
		          with: {
				          ('class_name' -> 'GenieMethodFixture').
				          ('message_selector' -> 'oldThing').
				          ('new_message_selector' -> 'newThing') } asDictionary.
	self assert: (result at: 'success').
	self assert:
		((cls sourceCodeAt: #useThing) includesSubstring: 'self newThing').
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodFixture').
			('source' -> 'ping
	^ self').
			('protocol' -> 'tests') } asDictionary.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodFixture').
			('source' -> 'noisy
	self ping.
	self ping.
	^ 3').
			('protocol' -> 'tests') } asDictionary.
	result := self
		          invokeMethodRefactoring: 'remove_all_message_sends'
		          with: {
				          ('class_name' -> 'GenieMethodFixture').
				          ('method_name' -> 'noisy').
				          ('message_selector' -> 'ping') } asDictionary.
	self assert: (result at: 'success').
	source := cls sourceCodeAt: #noisy.
	self deny: (source includesSubstring: 'self ping').
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodFixture').
			('source' -> 'replacement
	^ 6').
			('protocol' -> 'tests') } asDictionary.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodFixture').
			('source' -> 'legacy
	^ 5').
			('protocol' -> 'tests') } asDictionary.
	result := self invokeMethodRefactoring: 'deprecate_method' with: {
			          ('class_name' -> 'GenieMethodFixture').
			          ('method_name' -> 'legacy').
			          ('new_method_name' -> 'replacement') } asDictionary.
	self assert: (result at: 'success').
	source := cls sourceCodeAt: #legacy.
	self assert: (source includesSubstring: 'deprecated:').
	self assert: (source includesSubstring: 'replacement')
]

{ #category : 'tests' }
GenieActionTest >> testMethodRefactoringToolsMoveAndHierarchy [

	| fixture target parent child result |
	self invoke: #handleDefineClass: with: {
			('class_name' -> 'GenieMethodFixture').
			('superclass_name' -> 'Object').
			('fields' -> '').
			('package_name' -> 'Genie-Fixtures') } asDictionary.
	self invoke: #handleDefineClass: with: {
			('class_name' -> 'GenieMethodTarget').
			('superclass_name' -> 'Object').
			('fields' -> '').
			('package_name' -> 'Genie-Fixtures') } asDictionary.
	fixture := Smalltalk classNamed: 'GenieMethodFixture'.
	target := Smalltalk classNamed: 'GenieMethodTarget'.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodFixture').
			('source' -> 'movedValue
	^ 7').
			('protocol' -> 'tests') } asDictionary.
	result := self
		          invokeMethodRefactoring: 'move_method_to_class'
		          with: {
				          ('class_name' -> 'GenieMethodFixture').
				          ('method_name' -> 'movedValue').
				          ('target_class_name' -> 'GenieMethodTarget') }
				          asDictionary.
	self assert: (result at: 'success').
	self deny: (fixture includesSelector: #movedValue).
	self assert: (target includesSelector: #movedValue).
	self assert: target new movedValue equals: 7.
	self invoke: #handleDefineClass: with: {
			('class_name' -> 'GenieMethodParent').
			('superclass_name' -> 'Object').
			('fields' -> '').
			('package_name' -> 'Genie-Fixtures') } asDictionary.
	self invoke: #handleDefineClass: with: {
			('class_name' -> 'GenieMethodChild').
			('superclass_name' -> 'GenieMethodParent').
			('fields' -> '').
			('package_name' -> 'Genie-Fixtures') } asDictionary.
	parent := Smalltalk classNamed: 'GenieMethodParent'.
	child := Smalltalk classNamed: 'GenieMethodChild'.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodChild').
			('source' -> 'pulledValue
	^ 9').
			('protocol' -> 'tests') } asDictionary.
	result := self invokeMethodRefactoring: 'pull_up_method' with: {
			          ('class_name' -> 'GenieMethodChild').
			          ('method_name' -> 'pulledValue') } asDictionary.
	self assert: (result at: 'success').
	self assert: (parent includesSelector: #pulledValue).
	self deny: (child includesSelector: #pulledValue).
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodParent').
			('source' -> 'obsolete
	^ 1').
			('protocol' -> 'tests') } asDictionary.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodChild').
			('source' -> 'obsolete
	^ 2').
			('protocol' -> 'tests') } asDictionary.
	result := self
		          invokeMethodRefactoring: 'remove_methods_in_hierarchy'
		          with: {
				          ('class_name' -> 'GenieMethodParent').
				          ('method_name' -> 'obsolete') } asDictionary.
	self assert: (result at: 'success').
	self deny: (parent includesSelector: #obsolete).
	self deny: (child includesSelector: #obsolete)
]

{ #category : 'tests' }
GenieActionTest >> testMethodRefactoringToolsMoveMethodsBetweenOwners [

	| fixture target parent child sibling result source |
	self invoke: #handleDefineClass: with: {
			('class_name' -> 'GenieMethodTarget').
			('superclass_name' -> 'Object').
			('fields' -> '').
			('package_name' -> 'Genie-Fixtures') } asDictionary.
	self invoke: #handleDefineClass: with: {
			('class_name' -> 'GenieMethodFixture').
			('superclass_name' -> 'Object').
			('fields' -> 'component').
			('package_name' -> 'Genie-Fixtures') } asDictionary.
	fixture := Smalltalk classNamed: 'GenieMethodFixture'.
	target := Smalltalk classNamed: 'GenieMethodTarget'.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodTarget').
			('source' -> 'value
	^ 5').
			('protocol' -> 'tests') } asDictionary.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodFixture').
			('source' -> 'component: anObject
	component := anObject').
			('protocol' -> 'tests') } asDictionary.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodFixture').
			('source' -> 'componentValue
	^ component value + 1').
			('protocol' -> 'tests') } asDictionary.
	result := self invokeMethodRefactoring: 'move_method' with: {
			          ('class_name' -> 'GenieMethodFixture').
			          ('method_name' -> 'componentValue').
			          ('variable_name' -> 'component').
			          ('new_method_name' -> 'componentValue').
			          ('variable_type_names' -> #( 'GenieMethodTarget' )) }
			          asDictionary.
	self assert: (result at: 'success').
	self assert: (target includesSelector: #componentValue).
	source := fixture sourceCodeAt: #componentValue.
	self assert: (source includesSubstring: 'component componentValue').
	self assert: target new componentValue equals: 6.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodFixture').
			('source' -> 'classSideValue
	^ 12').
			('protocol' -> 'tests') } asDictionary.
	result := self
		          invokeMethodRefactoring: 'move_method_to_class_side'
		          with: {
				          ('class_name' -> 'GenieMethodFixture').
				          ('method_name' -> 'classSideValue') } asDictionary.
	self assert: (result at: 'success').
	self assert: (fixture class includesSelector: #classSideValue).
	self assert: fixture classSideValue equals: 12.
	fixture class compile: 'instanceSideValue
	^ 13' classified: 'tests'.
	result := self
		          invokeMethodRefactoring: 'move_method_to_instance_side'
		          with: {
				          ('class_name' -> 'GenieMethodFixture').
				          ('method_name' -> 'instanceSideValue') } asDictionary.
	self assert: (result at: 'success').
	self assert: (fixture includesSelector: #instanceSideValue).
	self assert: fixture new instanceSideValue equals: 13.
	self invoke: #handleDefineClass: with: {
			('class_name' -> 'GenieMethodParent').
			('superclass_name' -> 'Object').
			('fields' -> '').
			('package_name' -> 'Genie-Fixtures') } asDictionary.
	self invoke: #handleDefineClass: with: {
			('class_name' -> 'GenieMethodChild').
			('superclass_name' -> 'GenieMethodParent').
			('fields' -> '').
			('package_name' -> 'Genie-Fixtures') } asDictionary.
	self invoke: #handleDefineClass: with: {
			('class_name' -> 'GenieMethodSibling').
			('superclass_name' -> 'GenieMethodParent').
			('fields' -> '').
			('package_name' -> 'Genie-Fixtures') } asDictionary.
	parent := Smalltalk classNamed: 'GenieMethodParent'.
	child := Smalltalk classNamed: 'GenieMethodChild'.
	sibling := Smalltalk classNamed: 'GenieMethodSibling'.
	parent class compile: 'isAbstract
	^ true' classified: 'testing'.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodParent').
			('source' -> 'pushedValue
	^ 17').
			('protocol' -> 'tests') } asDictionary.
	result := self invokeMethodRefactoring: 'push_down_method' with: {
			          ('class_name' -> 'GenieMethodParent').
			          ('method_name' -> 'pushedValue') } asDictionary.
	self assert: (result at: 'success').
	self assert: (child includesSelector: #pushedValue).
	self assert: (sibling includesSelector: #pushedValue).
	self assert: child new pushedValue equals: 17.
	self assert: sibling new pushedValue equals: 17
]

{ #category : 'tests' }
GenieActionTest >> testMethodRefactoringToolsParametersAndMessages [

	| cls result |
	self invoke: #handleDefineClass: with: {
			('class_name' -> 'GenieMethodFixture').
			('superclass_name' -> 'Object').
			('fields' -> '').
			('package_name' -> 'Genie-Fixtures') } asDictionary.
	cls := Smalltalk classNamed: 'GenieMethodFixture'.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodFixture').
			('source' -> 'addBase
	^ 1').
			('protocol' -> 'tests') } asDictionary.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodFixture').
			('source' -> 'useAddBase
	^ self addBase').
			('protocol' -> 'tests') } asDictionary.
	result := self invokeMethodRefactoring: 'add_parameter' with: {
			          ('class_name' -> 'GenieMethodFixture').
			          ('method_name' -> 'addBase').
			          ('new_method_name' -> 'addBase:').
			          ('parameter_name' -> 'ignored').
			          ('default_value' -> 'nil') } asDictionary.
	self assert: (result at: 'success').
	self assert: (cls includesSelector: #addBase:).
	self assert:
		((cls sourceCodeAt: #useAddBase) includesSubstring: 'addBase: nil').
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodFixture').
			('source' -> 'removeBase: ignored
	^ 2').
			('protocol' -> 'tests') } asDictionary.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodFixture').
			('source' -> 'useRemoveBase
	^ self removeBase: nil').
			('protocol' -> 'tests') } asDictionary.
	result := self invokeMethodRefactoring: 'remove_parameter' with: {
			          ('class_name' -> 'GenieMethodFixture').
			          ('method_name' -> 'removeBase:').
			          ('parameter_name' -> 'ignored').
			          ('new_method_name' -> 'removeBase') } asDictionary.
	self assert: (result at: 'success').
	self assert: (cls includesSelector: #removeBase).
	self assert: ((cls sourceCodeAt: #useRemoveBase) includesSubstring:
			 'self removeBase').
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodFixture').
			('source' -> 'literalValue: aNumber
	^ aNumber + 1').
			('protocol' -> 'tests') } asDictionary.
	self invoke: #handleDefineMethod: with: {
			('class_name' -> 'GenieMethodFixture').
			('source' -> 'useLiteral
	^ self literalValue: 4').
			('protocol' -> 'tests') } asDictionary.
	result := self invokeMethodRefactoring: 'inline_parameter' with: {
			          ('class_name' -> 'GenieMethodFixture').
			          ('method_name' -> 'literalValue:').
			          ('parameter_name' -> 'aNumber') } asDictionary.
	self assert: (result at: 'success').
	self assert: (cls includesSelector: #literalValue).
	self assert:
		((cls sourceCodeAt: #literalValue) includesSubstring: 'aNumber := 4').
	self assert: ((cls sourceCodeAt: #useLiteral) includesSubstring:
			 'self literalValue')
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
GenieActionTest >> testVariableRefactoringToolsClassVariableAliases [

	| targetClass names result |
	self invoke: #handleDefineClass: with: {
			('class_name' -> 'GenieVarFixture').
			('superclass_name' -> 'Object').
			('fields' -> '').
			('package_name' -> 'Genie-Fixtures') } asDictionary.
	targetClass := Smalltalk classNamed: 'GenieVarFixture'.
	result := self
		          invokeVariableRefactoring: 'add_class_variable'
		          with: {
				          ('class_name' -> 'GenieVarFixture').
				          ('variable_name' -> 'RemoveMe') } asDictionary.
	self assert: (result at: 'success').
	self assert:
		((targetClass classVarNames collect: #asString) includes: 'RemoveMe').
	result := self
		          invokeVariableRefactoring: 'remove_class_variable'
		          with: {
				          ('class_name' -> 'GenieVarFixture').
				          ('variable_name' -> 'RemoveMe') } asDictionary.
	self assert: (result at: 'success').
	self deny:
		((targetClass classVarNames collect: #asString) includes: 'RemoveMe').
	result := self
		          invokeVariableRefactoring: 'add_class_variable'
		          with: {
				          ('class_name' -> 'GenieVarFixture').
				          ('variable_name' -> 'SharedOld') } asDictionary.
	self assert: (result at: 'success').
	result := self
		          invokeVariableRefactoring: 'rename_shared_variable'
		          with: {
				          ('class_name' -> 'GenieVarFixture').
				          ('variable_name' -> 'SharedOld').
				          ('new_variable_name' -> 'SharedNew') } asDictionary.
	self assert: (result at: 'success').
	names := targetClass classVarNames collect: #asString.
	self deny: (names includes: 'SharedOld').
	self assert: (names includes: 'SharedNew')
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
