Class {
	#name : 'GenieServer',
	#superclass : 'Object',
	#instVars : [
		'teapot',
		'teapotConfig',
		'settings',
		'announcer'
	],
	#classInstVars : [
		'current'
	],
	#category : 'Genie',
	#package : 'Genie'
}

{ #category : 'instance creation' }
GenieServer class >> configure: teapotConfigDict [
	| inst |
	inst := self new.
	inst teapotConfig: teapotConfigDict.
	^ inst
]

{ #category : 'instance creation' }
GenieServer class >> createStarted [
	| inst |
	inst := self configure: { #defaultOutput -> #json. #port -> 8087 } asDictionary.
	inst start.
	^ inst
]

{ #category : 'accessing' }
GenieServer class >> current [
	^ current ifNil: [ current := self createStarted ]
]

{ #category : 'accessing' }
GenieServer class >> current: anObject [
	current := anObject
]

{ #category : 'defaults' }
GenieServer class >> defaultSettingsCopied [
	^ GenieSettings defaultCopied
]

{ #category : 'class initialization' }
GenieServer class >> initialize [
	SessionManager default registerUserClassNamed: self name
]

{ #category : 'resetting' }
GenieServer class >> restart [
	self current stop.
	self current: nil.
	self current start
]

{ #category : 'system startup' }
GenieServer class >> startUp: isImageStarting [
	isImageStarting ifFalse: [ ^ self ].
	current ifNotNil: [ current stop ].
	current := nil.
	Smalltalk session addDeferredStartupAction: [ self current ]
]

{ #category : 'security' }
GenieServer >> allowDangerousTools [
	^ self settings at: #allowDangerousTools ifAbsent: [ true ]
]

{ #category : 'private' }
GenieServer >> asCamelCase: aString [
	^ (aString copyReplaceAll: '_' with: ' ') asCamelCase uncapitalized
]

{ #category : 'security' }
GenieServer >> authToken [
	^ self settings at: #authToken ifAbsent: [ '' ]
]

{ #category : 'security' }
GenieServer >> bindingAddress [
	"Socket address for the listening socket, from the bindingInterface setting.
	 Empty string means all interfaces; the default is IPv4 loopback (127.0.0.1)."
	| iface |
	iface := self bindingInterface.
	(iface isNil or: [ iface isEmpty ]) ifTrue: [ ^ nil ].
	(iface = '127.0.0.1' or: [ iface asLowercase = 'localhost' ]) ifTrue: [ ^ NetNameResolver loopBackAddress ].
	^ NetNameResolver addressForName: iface
]

{ #category : 'security' }
GenieServer >> bindingInterface [
	^ self settings at: #bindingInterface ifAbsent: [ '127.0.0.1' ]
]

{ #category : 'factory' }
GenieServer >> createTeapot [
	^ (Teapot configure: self teapotConfig associations)
		POST: '/mcp' -> [ :req | self handleMcpHttp: req ];
		yourself
]

{ #category : 'security' }
GenieServer >> dangerousToolNames [
	^ #('eval' 'save_image' 'remove_class' 'remove_method')
]

{ #category : 'private' }
GenieServer >> formattedSource: source [
	"Pretty-print method source with the standard formatter. Fall back to the raw
	 source if it does not parse, so a genuine syntax error surfaces on compile."
	^ [ (RBParser parseMethod: source) formattedCode ]
		on: Error
		do: [ :e | source ]
]

{ #category : 'handling' }
GenieServer >> handleApplySettings: request [
	^ self returnResultDo: [
		| requestJson newSettings |
		requestJson := NeoJSONReader fromString: request entity contents.
		newSettings := requestJson at: #settings.
		newSettings keysAndValuesDo: [ :key :value | | settingsKey |
			settingsKey := self asCamelCase: key.
			self settings at: settingsKey asSymbol put: value ].
		'Settings applied successfully' ]
]

{ #category : 'handling' }
GenieServer >> handleDefineClass: request [
	^ self returnResultDo: [
		| name superclassName fields package superclass slots newClass |
		name := request at: #class_name.
		superclassName := request at: #superclass_name.
		fields := request at: #fields.
		package := request at: #package_name.
		superclass := Smalltalk classNamed: superclassName.
		superclass ifNil: [ self error: 'Unknown superclass: ' , superclassName ].
		slots := (fields substrings collect: [ :each | each asSymbol ]) asArray.
		newClass := ShiftClassInstaller make: [ :b |
			b name: name asSymbol; superclass: superclass; slots: slots; package: package ].
		newClass name asString ]
]

{ #category : 'handling' }
GenieServer >> handleDefineMethod: request [

	^ self returnResultDo: [
			  | className source protocol targetClass selector |
			  className := request at: #class_name.
			  source := request at: #source.
			  protocol := request
				              at: #protocol
				              ifAbsent: [ 'as yet unclassified' ].
			  targetClass := Smalltalk classNamed: className.
			  targetClass ifNil: [ self error: 'Unknown class: ' , className ].
			  selector := targetClass
				              compile: (self formattedSource: source)
				              classified: protocol.
			  selector asString ]
]

{ #category : 'handling' }
GenieServer >> handleEval: request [
	^ self returnResultDo: [
		| requestJson code |
		requestJson := NeoJSONReader fromString: request entity contents.
		code := requestJson at: #code.
		self class compiler evaluate: code ]
]

{ #category : 'handling' }
GenieServer >> handleExportPackage: request [
	^ self returnResultDo: [
		| packageName outputPath snapshot outputPathRef writer propsRef |
		packageName := request at: #package_name.
		outputPath := request at: #path.
		snapshot := (MCPackage named: packageName) snapshot.
		outputPathRef := outputPath asFileReference.
		writer := TonelWriter on: outputPathRef ensureCreateDirectory.
		writer writeSnapshot: snapshot.
		"Write the Tonel format marker so Metacello can load the exported repo;
		 TonelWriter writes the package dirs but not this project-level file."
		propsRef := outputPathRef / '.properties'.
		propsRef exists ifFalse: [
			propsRef writeStreamDo: [ :s | s nextPutAll: '{
	#format : #tonel
}' ] ].
		packageName , ' exported to: ' , outputPathRef absolutePath pathString ]
]

{ #category : 'handling' }
GenieServer >> handleGetClassComment: request [
	^ self returnResultDo: [
		| className class |
		className := request at: #class_name.
		class := Smalltalk globals at: className asSymbol.
		class comment ]
]

{ #category : 'handling' }
GenieServer >> handleGetClassSource: request [
	^ self returnResultDo: [
		| className targetClass |
		className := request at: #class_name.
		targetClass := Smalltalk globals at: className asSymbol.
		TonelWriter sourceCodeOf: targetClass ]
]

{ #category : 'handling' }
GenieServer >> handleGetMethodSource: request [
	^ self returnResultDo: [
		| tokens isClassMethod isClassSide className methodName targetClass |
		tokens := (request at: #class_name) findTokens: ' '.
		isClassMethod := (request at: #is_class_method ifAbsent: [ false ]) == true.
		isClassSide := tokens size = 2 or: [ isClassMethod ].
		className := tokens first.
		methodName := request at: #method_name.
		targetClass := Smalltalk globals at: className asSymbol.
		isClassSide ifTrue: [ targetClass := targetClass class ].
		targetClass sourceCodeAt: methodName asSymbol ]
]

{ #category : 'handling' }
GenieServer >> handleGetSettings: request [
	^ self returnResultDo: [
		| dict |
		dict := self settings asDictionary.
		(dict includesKey: #authToken)
			ifTrue: [ dict at: #authToken put: ((dict at: #authToken) isEmptyOrNil ifTrue: [ '' ] ifFalse: [ '***set***' ]) ].
		dict ]
]

{ #category : 'handling' }
GenieServer >> handleImportPackage: request [
	^ self returnResultDo: [
		| packageName sourcePath reader sourcePathRef |
		packageName := request at: #package_name.
		sourcePath := request at: #path.
		sourcePathRef := sourcePath asFileReference.
		reader := TonelReader on: sourcePathRef fileName: packageName.
		reader loadPackage.
		reader snapshot updatePackage: reader package.
		packageName , ' imported from: ' , sourcePathRef absolutePath pathString ]
]

{ #category : 'handling' }
GenieServer >> handleInstallProject: request [
	^ self returnResultDo: [
		| projectName repositoryUrl loadGroups loadOptions registration |
		projectName := request at: #project_name.
		repositoryUrl := request at: #repository_url.
		loadGroups := request at: #load_groups ifAbsent: [ '' ].
		loadOptions := (loadGroups findTokens: ',') collect: #trim.
		[ registration := Metacello new
			baseline: projectName;
			repository: repositoryUrl;
			load: loadOptions.
		'Installed: ' , registration printString ] on: MCMergeOrLoadWarning do: [ :ex | Error signal: ex description ] ]
]

{ #category : 'handling' }
GenieServer >> handleListClasses: request [
	^ self returnResultDo: [
		| packageName |
		packageName := request at: #package_name.
		((self packageOrganizer packageNamed: packageName)
			classes collect: [ :each | each name ]) sorted ]
]

{ #category : 'handling' }
GenieServer >> handleListExtendedClasses: request [
	^ self returnResultDo: [
		| packageName |
		packageName := request at: #package_name.
		(self packageOrganizer packageNamed: packageName) extendedClassNames sorted ]
]

{ #category : 'handling' }
GenieServer >> handleListMethods: request [
	^ self returnResultDo: [
		| packageName |
		packageName := request at: #package_name.
		((self packageOrganizer packageNamed: packageName)
			methods collect: [ :each | each printString ]) sorted ]
]

{ #category : 'handling' }
GenieServer >> handleListPackages: request [
	^ self returnResultDo: [
		(Smalltalk packages collect: [ :each | each name ]) sorted ]
]

{ #category : 'handling' }
GenieServer >> handleMcpHttp: request [
	| message response json resp negotiatedVersion |
	(self originAllowed: request headers)
		ifFalse: [ ^ ZnResponse new statusLine: (ZnStatusLine code: 403); yourself ].
	(self headersAuthorized: request headers)
		ifFalse: [ ^ ZnResponse new statusLine: (ZnStatusLine code: 401); yourself ].
	message := NeoJSONReader fromString: request entity contents.
	negotiatedVersion := (request headers includesKey: 'MCP-Protocol-Version')
		ifTrue: [ request headers at: 'MCP-Protocol-Version' ]
		ifFalse: [ (message at: 'params' ifAbsent: [ Dictionary new ]) at: 'protocolVersion' ifAbsent: [ '2025-11-25' ] ].
	response := self handleMcpMessage: message.
	response ifNil: [ ^ ZnResponse new statusLine: (ZnStatusLine code: 202); yourself ].
	json := String streamContents: [ :s | (NeoJSONWriter on: s) nextPut: response ].
	resp := ZnResponse ok: (ZnEntity with: json type: ZnMimeType applicationJson).
	resp headers at: 'MCP-Protocol-Version' put: negotiatedVersion.
	^ resp
]

{ #category : 'mcp - protocol' }
GenieServer >> handleMcpMessage: aMessage [
	| method id params |
	method := aMessage at: 'method' ifAbsent: [ nil ].
	id := aMessage at: 'id' ifAbsent: [ nil ].
	params := aMessage at: 'params' ifAbsent: [ Dictionary new ].
	method = 'initialize' ifTrue: [ ^ self mcpInitialize: params id: id ].
	method = 'tools/list' ifTrue: [ ^ self mcpToolsList: id ].
	method = 'tools/call' ifTrue: [ ^ self mcpToolsCall: params id: id ].
	method = 'ping' ifTrue: [ ^ self jsonRpc: Dictionary new id: id ].
	(method notNil and: [ method beginsWith: 'notifications/' ]) ifTrue: [ ^ nil ].
	^ self jsonRpcError: -32601 message: 'Method not found: ' , method asString id: id
]

{ #category : 'handling' }
GenieServer >> handleRemoveClass: request [
	^ self returnResultDo: [
		| className targetClass |
		className := request at: #class_name.
		targetClass := Smalltalk classNamed: className.
		targetClass ifNil: [ self error: 'Unknown class: ' , className ].
		targetClass removeFromSystem.
		className ]
]

{ #category : 'handling' }
GenieServer >> handleRemoveMethod: request [
	^ self returnResultDo: [
		| className selector targetClass isClassSide |
		className := request at: #class_name.
		selector := request at: #method_name.
		isClassSide := (request at: #is_class_method ifAbsent: [ false ]) == true.
		targetClass := Smalltalk classNamed: className.
		targetClass ifNil: [ self error: 'Unknown class: ' , className ].
		isClassSide ifTrue: [ targetClass := targetClass class ].
		(targetClass includesSelector: selector asSymbol)
			ifFalse: [ self error: 'No such method: ' , className , '>>' , selector ].
		targetClass removeSelector: selector asSymbol.
		selector asString ]
]

{ #category : 'handling' }
GenieServer >> handleRenameClass: request [
	^ self returnResultDo: [
		| oldName newName |
		oldName := request at: #class_name.
		newName := request at: #new_class_name.
		(Smalltalk classNamed: oldName) ifNil: [ self error: 'Unknown class: ' , oldName ].
		(Smalltalk includesKey: #ReRenameClassRefactoring)
			ifTrue: [ ((Smalltalk classNamed: #ReRenameClassRefactoring) rename: oldName asSymbol to: newName asSymbol) execute ]
			ifFalse: [ ((Smalltalk classNamed: #RBRenameClassRefactoring) rename: (Smalltalk classNamed: oldName) to: newName asSymbol) execute ].
		newName ]
]

{ #category : 'handlers' }
GenieServer >> handleRenameMethod: request [

	^ self returnResultDo: [
			  | className oldSelector newSelector isClassSide targetClass permutation refactoringClass |
			  className := request at: #class_name.
			  oldSelector := (request at: #method_name) asSymbol.
			  newSelector := (request at: #new_method_name) asSymbol.
			  isClassSide := (request at: #is_class_method ifAbsent: [ false ])
			                 == true.
			  targetClass := Smalltalk classNamed: className.
			  targetClass ifNil: [ self error: 'Unknown class: ' , className ].
			  isClassSide ifTrue: [ targetClass := targetClass class ].
			  (targetClass includesSelector: oldSelector) ifFalse: [
					  self error:
						  'No such method: ' , className , '>>' , oldSelector asString ].
			  oldSelector numArgs = newSelector numArgs ifFalse: [
					  self error:
						  'Selectors must have the same arity: ' , oldSelector asString
						  , ' and ' , newSelector asString ].
			  permutation := request
				                 at: #permutation
				                 ifAbsent: [ 1 to: oldSelector numArgs ].
			  permutation := permutation collect: [ :each | each asInteger ].
			  refactoringClass := (Smalltalk includesKey:
				                       #RBRenameMethodTransformation)
				                      ifTrue: [
				                      Smalltalk classNamed:
					                      #RBRenameMethodTransformation ]
				                      ifFalse: [
				                      Smalltalk classNamed:
					                      #ReRenameMethodRefactoring ].
			  (refactoringClass
				   renameMethod: oldSelector
				   in: targetClass
				   to: newSelector
				   permutation: permutation) execute.
			  newSelector asString ]
]

{ #category : 'handling' }
GenieServer >> handleRunTest: request [
	^ self returnResultDo: [
		| className packageName |
		className := request at: #class_name ifAbsent: [ nil ].
		packageName := request at: #package_name ifAbsent: [ nil ].
		(className isNil and: [ packageName isNil ])
			ifTrue: [ self error: 'Provide class_name or package_name' ].
		self runStructuredTestSuite: (self testSuiteForClass: className package: packageName) ]
]

{ #category : 'handling' }
GenieServer >> handleSaveImage: request [
	^ self returnResultDo: [
		| className packageName report shouldSave snap resuming |
		className := request at: #test_class ifAbsent: [ nil ].
		packageName := request at: #test_package ifAbsent: [ nil ].
		report := nil.
		shouldSave := true.
		(className notNil or: [ packageName notNil ]) ifTrue: [
			report := self runStructuredTestSuite: (self testSuiteForClass: className package: packageName).
			shouldSave := ((report at: 'failed') + (report at: 'errored')) = 0 ].
		shouldSave ifTrue: [
			snap := Smalltalk snapshot: true andQuit: false.
			"Older Pharo returns a Boolean (isImageStarting); Pharo 12+ returns a SnapshotOperation.
			 True/non-nil only when the image is later resumed from this snapshot — the original
			 request socket is long dead, so just stop."
			resuming := (snap isKindOf: Boolean)
				ifTrue: [ snap ]
				ifFalse: [ (snap respondsTo: #isImageStarting) and: [ snap isImageStarting ] ].
			resuming ifTrue: [ Processor terminateActive ] ].
		{ 'saved' -> shouldSave. 'tests' -> (report ifNil: [ 'not gated' ]) } asDictionary ]
]

{ #category : 'handling' }
GenieServer >> handleSearchClassesLike: request [
	^ self returnResultDo: [
		| query lower results |
		query := request at: #class_name_query.
		lower := query asLowercase.
		results := OrderedCollection new.
		SystemNavigation default allClasses do: [ :cls |
			(cls name asLowercase beginsWith: lower) ifTrue: [ results add: cls name ] ].
		results asSortedCollection asArray ]
]

{ #category : 'handling' }
GenieServer >> handleSearchImplementors: request [
	^ self returnResultDo: [
		| selector nav results |
		selector := request at: #method_name.
		nav := SystemNavigation default.
		results := OrderedCollection new.
		(nav allImplementorsOf: selector asSymbol) do: [ :method |
			results add: { ('class' -> method methodClass name). ('method' -> method selector). ('package' -> method package name) } asDictionary ].
		results asArray ]
]

{ #category : 'handling' }
GenieServer >> handleSearchMethodsLike: request [
	^ self returnResultDo: [
		| query nav results |
		query := request at: #method_name_query.
		nav := SystemNavigation default.
		results := OrderedCollection new.
		nav allSelectorsStartingWith: query do: [ :selector | results add: selector ].
		results ]
]

{ #category : 'handling' }
GenieServer >> handleSearchReferences: request [
	^ self returnResultDo: [
		| symbol nav |
		symbol := request at: #program_symbol.
		nav := SystemNavigation default.
		(nav allReferencesTo: symbol asSymbol) collect: [ :method |
			{ ('class' -> method methodClass name). ('method' -> method selector). ('package' -> method package name) } asDictionary ] ]
]

{ #category : 'handling' }
GenieServer >> handleSearchReferencesToClass: request [
	^ self returnResultDo: [
		| className nav targetClass |
		className := request at: #class_name.
		nav := SystemNavigation default.
		targetClass := Smalltalk globals at: className asSymbol.
		(targetClass allCallsOnIn: nav) collect: [ :method |
			{ ('class' -> method methodClass name). ('method' -> method selector). ('package' -> method package name) } asDictionary ] ]
]

{ #category : 'handling' }
GenieServer >> handleSearchTraitsLike: request [
	^ self returnResultDo: [
		| query lower |
		query := request at: #trait_name_query.
		lower := query asLowercase.
		(Smalltalk globals allTraits select: [ :trait | trait name asLowercase beginsWith: lower ])
			collect: [ :each | each name ] ]
]

{ #category : 'security' }
GenieServer >> headersAuthorized: aHeaders [
	"Opt-in bearer-token auth. With no authToken set every request is allowed;
	 when set, the request must carry Authorization: Bearer <token>."
	| token provided |
	token := self authToken.
	(token isNil or: [ token isEmpty ]) ifTrue: [ ^ true ].
	provided := (aHeaders includesKey: 'Authorization') ifTrue: [ aHeaders at: 'Authorization' ] ifFalse: [ '' ].
	^ provided = ('Bearer ' , token)
]

{ #category : 'mcp - protocol' }
GenieServer >> jsonRpc: aResult id: anId [
	^ { 'jsonrpc' -> '2.0'. 'id' -> anId. 'result' -> aResult } asDictionary
]

{ #category : 'mcp - protocol' }
GenieServer >> jsonRpcError: aCode message: aMessage id: anId [
	^ { 'jsonrpc' -> '2.0'. 'id' -> anId.
	    'error' -> { 'code' -> aCode. 'message' -> aMessage } asDictionary } asDictionary
]

{ #category : 'mcp - protocol' }
GenieServer >> mcpInitialize: params id: anId [
	| version |
	version := params at: 'protocolVersion' ifAbsent: [ '2025-11-25' ].
	^ self jsonRpc: { 'protocolVersion' -> version.
		'capabilities' -> { 'tools' -> Dictionary new } asDictionary.
		'serverInfo' -> { 'name' -> 'genie'. 'version' -> '1.0.0' } asDictionary } asDictionary
		id: anId
]

{ #category : 'mcp - tools' }
GenieServer >> mcpTool: aName description: aDesc selector: aSelector properties: propAssocs required: requiredNames [
	| props |
	props := Dictionary new.
	propAssocs do: [ :assoc | props at: assoc key put: { 'type' -> assoc value } asDictionary ].
	^ { 'name' -> aName.
	    'description' -> aDesc.
	    'selector' -> aSelector.
	    'inputSchema' -> { 'type' -> 'object'. 'properties' -> props. 'required' -> requiredNames } asDictionary } asDictionary
]

{ #category : 'mcp - tools' }
GenieServer >> mcpToolSpecs [

	^ {
		  (self
			   mcpTool: 'eval'
			   description:
			   'Evaluate a Pharo Smalltalk expression and return the result.'
			   selector: #handleEval:
			   properties: { ('code' -> 'string') }
			   required: #( 'code' )).
		  (self
			   mcpTool: 'define_class'
			   description: 'Define (or redefine) a class.'
			   selector: #handleDefineClass:
			   properties: {
					   ('class_name' -> 'string').
					   ('superclass_name' -> 'string').
					   ('fields' -> 'string').
					   ('package_name' -> 'string') }
			   required:
			   #( 'class_name' 'superclass_name' 'fields' 'package_name' )).
		  (self
			   mcpTool: 'define_method'
			   description: 'Compile a method into a class.'
			   selector: #handleDefineMethod:
			   properties: {
					   ('class_name' -> 'string').
					   ('source' -> 'string').
					   ('protocol' -> 'string') }
			   required: #( 'class_name' 'source' )).
		  (self
			   mcpTool: 'remove_class'
			   description: 'Remove a class from the system.'
			   selector: #handleRemoveClass:
			   properties: { ('class_name' -> 'string') }
			   required: #( 'class_name' )).
		  (self
			   mcpTool: 'remove_method'
			   description: 'Remove a method from a class.'
			   selector: #handleRemoveMethod:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string').
					   ('is_class_method' -> 'boolean') }
			   required: #( 'class_name' 'method_name' )).
		  (self
			   mcpTool: 'rename_class'
			   description:
			   'Rename a class and update all references across the image (uses the refactoring engine).'
			   selector: #handleRenameClass:
			   properties: {
					   ('class_name' -> 'string').
					   ('new_class_name' -> 'string') }
			   required: #( 'class_name' 'new_class_name' )).
		  (self
			   mcpTool: 'rename_method'
			   description:
			   'Rename a method and update senders across the image (uses the refactoring engine). Same-arity renames use identity argument order unless permutation is supplied.'
			   selector: #handleRenameMethod:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string').
					   ('new_method_name' -> 'string').
					   ('is_class_method' -> 'boolean').
					   ('permutation' -> 'array') }
			   required: #( 'class_name' 'method_name' 'new_method_name' )).
		  (self
			   mcpTool: 'run_test'
			   description:
			   'Run tests for a class or package; structured pass/fail/error counts.'
			   selector: #handleRunTest:
			   properties: {
					   ('class_name' -> 'string').
					   ('package_name' -> 'string') }
			   required: #(  )).
		  (self
			   mcpTool: 'save_image'
			   description:
			   'Save the Pharo image to disk. Optionally pass test_class or test_package to gate the save on tests: runs them first and saves only if all pass. Returns { saved, tests }.'
			   selector: #handleSaveImage:
			   properties: {
					   ('test_class' -> 'string').
					   ('test_package' -> 'string') }
			   required: #(  )).
		  (self
			   mcpTool: 'list_packages'
			   description: 'List all package names.'
			   selector: #handleListPackages:
			   properties: {  }
			   required: #(  )).
		  (self
			   mcpTool: 'list_classes'
			   description: 'List classes in a package.'
			   selector: #handleListClasses:
			   properties: { ('package_name' -> 'string') }
			   required: #( 'package_name' )).
		  (self
			   mcpTool: 'list_methods'
			   description: 'List methods in a package.'
			   selector: #handleListMethods:
			   properties: { ('package_name' -> 'string') }
			   required: #( 'package_name' )).
		  (self
			   mcpTool: 'list_extended_classes'
			   description: 'List extended classes in a package.'
			   selector: #handleListExtendedClasses:
			   properties: { ('package_name' -> 'string') }
			   required: #( 'package_name' )).
		  (self
			   mcpTool: 'get_class_source'
			   description: 'Get the full source of a class.'
			   selector: #handleGetClassSource:
			   properties: { ('class_name' -> 'string') }
			   required: #( 'class_name' )).
		  (self
			   mcpTool: 'get_method_source'
			   description:
			   'Get the source of a method. is_class_method=true for class-side.'
			   selector: #handleGetMethodSource:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string').
					   ('is_class_method' -> 'boolean') }
			   required: #( 'class_name' 'method_name' )).
		  (self
			   mcpTool: 'get_class_comment'
			   description: 'Get the comment of a class.'
			   selector: #handleGetClassComment:
			   properties: { ('class_name' -> 'string') }
			   required: #( 'class_name' )).
		  (self
			   mcpTool: 'search_classes_like'
			   description: 'Find classes whose name starts with a query.'
			   selector: #handleSearchClassesLike:
			   properties: { ('class_name_query' -> 'string') }
			   required: #( 'class_name_query' )).
		  (self
			   mcpTool: 'search_methods_like'
			   description: 'Find selectors starting with a query.'
			   selector: #handleSearchMethodsLike:
			   properties: { ('method_name_query' -> 'string') }
			   required: #( 'method_name_query' )).
		  (self
			   mcpTool: 'search_implementors'
			   description: 'Find all implementors of a selector.'
			   selector: #handleSearchImplementors:
			   properties: { ('method_name' -> 'string') }
			   required: #( 'method_name' )).
		  (self
			   mcpTool: 'search_references'
			   description: 'Find references to a selector or symbol.'
			   selector: #handleSearchReferences:
			   properties: { ('program_symbol' -> 'string') }
			   required: #( 'program_symbol' )).
		  (self
			   mcpTool: 'search_references_to_class'
			   description: 'Find references to a class.'
			   selector: #handleSearchReferencesToClass:
			   properties: { ('class_name' -> 'string') }
			   required: #( 'class_name' )).
		  (self
			   mcpTool: 'search_traits_like'
			   description: 'Find traits whose name starts with a query.'
			   selector: #handleSearchTraitsLike:
			   properties: { ('trait_name_query' -> 'string') }
			   required: #( 'trait_name_query' )).
		  (self
			   mcpTool: 'get_settings'
			   description: 'Get the current server settings.'
			   selector: #handleGetSettings:
			   properties: {  }
			   required: #(  )).
		  (self
			   mcpTool: 'apply_settings'
			   description:
			   'Apply server settings from a { settings: {...} } object.'
			   selector: #handleApplySettings:
			   properties: { ('settings' -> 'object') }
			   required: #( 'settings' )).
		  (self
			   mcpTool: 'export_package'
			   description:
			   'Export a package to Tonel format at a filesystem path.'
			   selector: #handleExportPackage:
			   properties: {
					   ('package_name' -> 'string').
					   ('path' -> 'string') }
			   required: #( 'package_name' 'path' )).
		  (self
			   mcpTool: 'import_package'
			   description: 'Import a Tonel package from a filesystem path.'
			   selector: #handleImportPackage:
			   properties: {
					   ('package_name' -> 'string').
					   ('path' -> 'string') }
			   required: #( 'package_name' 'path' )).
		  (self
			   mcpTool: 'install_project'
			   description:
			   'Install a project via Metacello baseline from a repository URL.'
			   selector: #handleInstallProject:
			   properties: {
					   ('project_name' -> 'string').
					   ('repository_url' -> 'string').
					   ('load_groups' -> 'string') }
			   required: #( 'project_name' 'repository_url' )) }
]

{ #category : 'mcp - protocol' }
GenieServer >> mcpToolsCall: params id: anId [
	| toolName arguments spec result text |
	toolName := params at: 'name'.
	(self allowDangerousTools not and: [ self dangerousToolNames includes: toolName ])
		ifTrue: [ ^ self jsonRpcError: -32600 message: 'Tool disabled: ' , toolName , ' (allowDangerousTools is off)' id: anId ].
	arguments := params at: 'arguments' ifAbsent: [ Dictionary new ].
	spec := self mcpToolSpecs detect: [ :s | (s at: 'name') = toolName ] ifNone: [ nil ].
	spec ifNil: [ ^ self jsonRpcError: -32602 message: 'Unknown tool: ' , toolName id: anId ].
	result := self perform: (spec at: 'selector') with: (Wish new setArguments: arguments).
	text := String streamContents: [ :s | (NeoJSONWriter on: s) nextPut: result ].
	^ self jsonRpc: { 'content' -> { { 'type' -> 'text'. 'text' -> text } asDictionary }.
		'isError' -> (result at: 'success') not } asDictionary id: anId
]

{ #category : 'mcp - protocol' }
GenieServer >> mcpToolsList: anId [
	| tools |
	tools := self mcpToolSpecs collect: [ :spec |
		{ 'name' -> (spec at: 'name').
		  'description' -> (spec at: 'description').
		  'inputSchema' -> (spec at: 'inputSchema') } asDictionary ].
	^ self jsonRpc: { 'tools' -> tools asArray } asDictionary id: anId
]

{ #category : 'security' }
GenieServer >> originAllowed: aHeaders [
	"Defense-in-depth against browser DNS-rebinding: reject a non-local Origin.
	 Requests with no Origin header (curl, MCP clients) pass; the auth token is the real gate."
	| origin |
	origin := (aHeaders includesKey: 'Origin') ifTrue: [ aHeaders at: 'Origin' ] ifFalse: [ nil ].
	origin ifNil: [ ^ true ].
	^ (origin includesSubstring: 'localhost') or: [ origin includesSubstring: '127.0.0.1' ]
]

{ #category : 'accessing' }
GenieServer >> packageOrganizer [
	^ (Smalltalk includesKey: #PackageOrganizer)
		ifTrue: [ (Smalltalk classNamed: #PackageOrganizer) default ]
		ifFalse: [ (Smalltalk classNamed: #RPackageOrganizer) default ]
]

{ #category : 'private' }
GenieServer >> receiverErrorInfoFrom: receiverObject [
	| receiverErrorInfo values |
	receiverErrorInfo := Dictionary new.
	receiverErrorInfo at: 'self' put: receiverObject asString.
	receiverErrorInfo at: 'class' put: receiverObject className.
	values := Dictionary new.
	receiverObject class allInstVarNames do: [ :nm | values at: nm put: (receiverObject instVarNamed: nm) asString ].
	receiverErrorInfo at: 'variables' put: values.
	^ receiverErrorInfo
]

{ #category : 'private' }
GenieServer >> returnError: anError by: resultDict [
	| errorInfo signalerContext |
	errorInfo := Dictionary new.
	errorInfo at: 'description' put: anError description.
	signalerContext := anError signalerContext.
	errorInfo at: 'stack_trace' put: (String streamContents: [:strm | signalerContext debugStack: self stackSize on: strm]).
	errorInfo at: 'receiver' put: (self receiverErrorInfoFrom: signalerContext receiver).
	resultDict at: 'error' put: errorInfo.
	^ resultDict
]

{ #category : 'private' }
GenieServer >> returnResultDo: aBlock [
	| resultDict |
	resultDict := { ('success' -> false) } asDictionary.
	[ resultDict at: 'result' put: aBlock value ]
		on: Error
		do: [ :ex | ^ self returnError: ex by: resultDict ].
	resultDict at: 'success' put: true.
	^ resultDict
]

{ #category : 'testing' }
GenieServer >> runStructuredTestSuite: aSuite [

	| details passed failed errored |
	details := OrderedCollection new.
	passed := 0.
	failed := 0.
	errored := 0.
	self suppressChangeLoggingDuring: [
			aSuite tests do: [ :tc |
					[
						tc runCase.
						passed := passed + 1 ]
						on: TestFailure , Error
						do: [ :e |
								| kind |
								kind := (e isKindOf: TestFailure)
									        ifTrue: [ 'failure' ]
									        ifFalse: [ 'error' ].
								kind = 'failure'
									ifTrue: [ failed := failed + 1 ]
									ifFalse: [ errored := errored + 1 ].
								details add: {
										('test' -> (tc class name asString , '>>' , tc selector)).
										('kind' -> kind).
										('message'
										 -> (e messageText ifNil: [ e class name asString ])) }
										asDictionary ] ] ].
	^ {
		  ('passed' -> passed).
		  ('failed' -> failed).
		  ('errored' -> errored).
		  ('total' -> aSuite tests size).
		  ('details' -> details asArray) } asDictionary
]

{ #category : 'accessing' }
GenieServer >> settings [
	^ settings ifNil: [ settings := self class defaultSettingsCopied ]
]

{ #category : 'accessing' }
GenieServer >> settings: anObject [
	settings := anObject
]

{ #category : 'accessing' }
GenieServer >> stackSize [
	^ self settings stackSize
]

{ #category : 'actions' }
GenieServer >> start [
	self bindingAddress ifNotNil: [ :addr | self teapot server bindingAddress: addr ].
	self teapot start
]

{ #category : 'actions' }
GenieServer >> stop [
	self teapot stop
]

{ #category : 'private' }
GenieServer >> suppressChangeLoggingDuring: aBlock [
	"Run aBlock without recording its class/method changes in the change log,
	 so test fixtures don't clutter the change set. Portable: runs aBlock directly
	 if the announcer has no block-scoped suspension."

	^ (SystemAnnouncer uniqueInstance respondsTo: #suspendAllWhile:)
		  ifTrue: [ SystemAnnouncer uniqueInstance suspendAllWhile: aBlock ]
		  ifFalse: [ aBlock value ]
]

{ #category : 'accessing' }
GenieServer >> teapot [
	^ teapot ifNil: [ teapot := self createTeapot ]
]

{ #category : 'accessing' }
GenieServer >> teapot: anObject [
	teapot := anObject
]

{ #category : 'accessing' }
GenieServer >> teapotConfig [
	^ teapotConfig
]

{ #category : 'accessing' }
GenieServer >> teapotConfig: anObject [
	teapotConfig := anObject
]

{ #category : 'testing' }
GenieServer >> testSuiteForClass: className package: packageName [
	^ className
		ifNotNil: [ (Smalltalk globals at: className asSymbol) suite ]
		ifNil: [ (self packageOrganizer packageNamed: packageName) testSuite ]
]
