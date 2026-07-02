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

{ #category : 'mcp tools' }
GenieServer >> allMcpToolSpecs [

	^ self mcpToolSpecs , self variableRefactoringToolSpecs
	  , self methodRefactoringToolSpecs
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

{ #category : 'private' }
GenieServer >> classFromRefactoringRequest: request [

	| className targetClass |
	className := request at: #class_name.
	targetClass := Smalltalk classNamed: className.
	targetClass ifNil: [ self error: 'Unknown class: ' , className ].
	^ targetClass
]

{ #category : 'private' }
GenieServer >> classVariableFromRefactoringRequest: request [

	^ (request at: #class_variable ifAbsent: [ false ]) == true
]

{ #category : 'method refactoring' }
GenieServer >> classesNamed: classNames [

	^ classNames collect: [ :className |
			  | targetClass |
			  targetClass := Smalltalk classNamed: className.
			  targetClass ifNil: [ self error: 'Unknown class: ' , className ].
			  targetClass ]
]

{ #category : 'method refactoring' }
GenieServer >> compiledMethodFor: selector class: targetClass classSide: isClassSide [

	| methodClass |
	methodClass := isClassSide
		               ifTrue: [ targetClass class ]
		               ifFalse: [ targetClass ].
	(methodClass includesSelector: selector) ifFalse: [
			self error:
				'Unknown method: ' , selector asString , ' in ' , methodClass name ].
	^ methodClass >> selector
]

{ #category : 'refactoring' }
GenieServer >> configureMethodRefactoringOptions: refactoring request: request [

	| newSelector argumentNames variableName selfArgumentName typeNames typeClasses |
	newSelector := request
		               at: #new_method_name
		               ifAbsent: [
		               request at: #method_name ifAbsent: [ nil ] ].
	newSelector ifNotNil: [
			argumentNames := request at: #argument_names ifAbsent: [ nil ].
			argumentNames ifNotNil: [
				argumentNames := argumentNames collect: [ :each | each asString ] ].
			refactoring setOption: #methodName toUse: [ :methodName :ignored |
					methodName selector: newSelector asSymbol.
					argumentNames ifNotNil: [ methodName arguments: argumentNames ].
					methodName yourself ] ].
	selfArgumentName := request at: #self_argument_name ifAbsent: [ nil ].
	selfArgumentName ifNotNil: [
			refactoring
				setOption: #selfArgumentName
				toUse: [ :ignored | selfArgumentName ] ].
	variableName := request at: #variable_name ifAbsent: [ nil ].
	variableName ifNotNil: [
			refactoring
				setOption: #selectVariableToMoveTo
				toUse: [ :ignored :class :selector | variableName ] ].
	typeNames := request at: #variable_type_names ifAbsent: [ nil ].
	typeClasses := typeNames ifNotNil: [
			               typeNames collect: [ :className |
					               | modelClass |
					               modelClass := refactoring model classNamed:
						                             className asString asSymbol.
					               modelClass ifNil: [
						               self error:
							               'Unknown class: ' , className asString ].
					               modelClass ] ].
	refactoring
		setOption: #variableTypes
		toUse: [ :ignored :initialTypes :selectedTypes |
			typeClasses ifNil: [ selectedTypes ] ifNotNil: [ typeClasses ] ].
	^ refactoring
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
GenieServer >> executeGenerateVariableAccessorsFor: request class: targetClass tool: toolName [

	| classVariable variableNames |
	classVariable := self classVariableFromRefactoringRequest: request.
	variableNames := request at: #variable_names ifAbsent: [
			                 classVariable
				                 ifTrue: [ targetClass classVarNames ]
				                 ifFalse: [ targetClass instVarNames ] ].
	variableNames do: [ :each |
			(ReCreateAccessorsForVariableTransformation
				 variable: each
				 class: targetClass
				 classVariable: classVariable) execute ].
	^ self
		  variableRefactoringResultForTool: toolName
		  request: request
		  variables: variableNames
]

{ #category : 'method refactoring' }
GenieServer >> executeMethodRefactoring: refactoring request: request [

	^ self
		  executeMethodRefactoring: refactoring
		  tool: (request at: #tool_name)
		  request: request
]

{ #category : 'method refactoring' }
GenieServer >> executeMethodRefactoring: refactoring tool: toolName request: request [

	refactoring execute.
	^ self methodRefactoringResultForTool: toolName request: request
]

{ #category : 'variable refactoring' }
GenieServer >> executeVariableRefactoring: refactoring request: request [

	^ self
		  executeVariableRefactoring: refactoring
		  tool: (request at: #tool_name)
		  request: request
		  variables: nil
]

{ #category : 'private' }
GenieServer >> executeVariableRefactoring: refactoring tool: toolName request: request variables: variableNames [

	refactoring execute.
	^ self
		  variableRefactoringResultForTool: toolName
		  request: request
		  variables: variableNames
]

{ #category : 'private' }
GenieServer >> formattedSource: source [
	"Pretty-print method source with the standard formatter. Fall back to the raw
	 source if it does not parse, so a genuine syntax error surfaces on compile."
	^ [ (RBParser parseMethod: source) formattedCode ]
		on: Error
		do: [ :e | source ]
]

{ #category : 'variable refactoring' }
GenieServer >> handleAddClassVariable: request [

	^ self returnResultDo: [
			  self
				  executeVariableRefactoring: (RBAddClassVariableRefactoring
						   variable: (request at: #variable_name)
						   class: (self classFromRefactoringRequest: request))
				  request: request ]
]

{ #category : 'variable refactoring' }
GenieServer >> handleAddInstanceVariable: request [

	^ self returnResultDo: [
			  self
				  executeVariableRefactoring: (RBAddInstanceVariableRefactoring
						   variable: (request at: #variable_name)
						   class: (self classFromRefactoringRequest: request))
				  request: request ]
]

{ #category : 'method refactoring' }
GenieServer >> handleAddParameter: request [

	^ self returnResultDo: [
			  | oldSelector newSelector permutation |
			  oldSelector := (request at: #method_name) asSymbol.
			  newSelector := (request at: #new_method_name) asSymbol.
			  permutation := self
				                 permutationFromMethodRefactoringRequest: request
				                 oldSelector: oldSelector
				                 newSelector: newSelector.
			  self
				  executeMethodRefactoring: (RBAddParameterRefactoring
						   addParameterToMethod: oldSelector
						   in: (self classFromRefactoringRequest: request)
						   newSelector: newSelector
						   permutation: permutation
						   newArgs:
						   (self newArgumentsFromMethodRefactoringRequest: request))
				  request: request ]
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

{ #category : 'method refactoring' }
GenieServer >> handleChangeMethodSignature: request [

	^ self returnResultDo: [
			  | oldSelector newSelector permutation |
			  oldSelector := (request at: #method_name) asSymbol.
			  newSelector := (request at: #new_method_name) asSymbol.
			  permutation := self
				                 permutationFromMethodRefactoringRequest: request
				                 oldSelector: oldSelector
				                 newSelector: newSelector.
			  self
				  executeMethodRefactoring: (ReRenameMethodRefactoring
						   renameMethod: oldSelector
						   in: (self classFromRefactoringRequest: request)
						   to: newSelector
						   permutation: permutation)
				  request: request ]
]

{ #category : 'method refactoring' }
GenieServer >> handleCreateCascade: request [

	^ self returnResultDo: [
			  self
				  executeMethodRefactoring: (RBCreateCascadeRefactoring
						   combine: (self intervalFromRefactoringRequest: request)
						   from: (request at: #method_name) asSymbol
						   in: (self classFromRefactoringRequest: request))
				  request: request ]
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

{ #category : 'method refactoring' }
GenieServer >> handleDeprecateMethod: request [

	^ self returnResultDo: [
			  self
				  executeMethodRefactoring: (RBDeprecateMethodTransformation
						   deprecateMethod: (request at: #method_name) asSymbol
						   in: (self classFromRefactoringRequest: request)
						   using: (request at: #new_method_name) asSymbol)
				  request: request ]
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

{ #category : 'method refactoring' }
GenieServer >> handleExtractMethod: request [

	^ self returnResultDo: [
			  | refactoring |
			  refactoring := RBExtractMethodRefactoring
				                 extract:
				                 (self intervalFromRefactoringRequest: request)
				                 from: (request at: #method_name) asSymbol
				                 in: (self classFromRefactoringRequest: request).
			  self
				  executeMethodRefactoring:
				  (self
					   configureMethodRefactoringOptions: refactoring
					   request: request)
				  request: request ]
]

{ #category : 'method refactoring' }
GenieServer >> handleExtractMethodAndOccurrences: request [

	^ self returnResultDo: [
			  | refactoring |
			  refactoring := RBExtractMethodAndOccurrences
				                 extract:
				                 (self intervalFromRefactoringRequest: request)
				                 from: (request at: #method_name) asSymbol
				                 in: (self classFromRefactoringRequest: request).
			  self
				  executeMethodRefactoring:
				  (self
					   configureMethodRefactoringOptions: refactoring
					   request: request)
				  request: request ]
]

{ #category : 'method refactoring' }
GenieServer >> handleExtractMethodToComponent: request [

	^ self returnResultDo: [
			  | refactoring |
			  refactoring := RBExtractMethodToComponentRefactoring
				                 extract:
				                 (self intervalFromRefactoringRequest: request)
				                 from: (request at: #method_name) asSymbol
				                 in: (self classFromRefactoringRequest: request).
			  self
				  executeMethodRefactoring:
				  (self
					   configureMethodRefactoringOptions: refactoring
					   request: request)
				  request: request ]
]

{ #category : 'method refactoring' }
GenieServer >> handleExtractSetupMethod: request [

	^ self returnResultDo: [
			  self
				  executeMethodRefactoring: (RBExtractSetUpMethodRefactoring
						   extract: (self intervalFromRefactoringRequest: request)
						   from: (request at: #method_name) asSymbol
						   in: (self classFromRefactoringRequest: request))
				  request: request ]
]

{ #category : 'method refactoring' }
GenieServer >> handleExtractSetupMethodAndOccurrences: request [

	^ self returnResultDo: [
			  self
				  executeMethodRefactoring: (RBExtractSetUpMethodAndOccurrences
						   extract: (self intervalFromRefactoringRequest: request)
						   from: (request at: #method_name) asSymbol
						   in: (self classFromRefactoringRequest: request))
				  request: request ]
]

{ #category : 'variable refactoring' }
GenieServer >> handleExtractTemporary: request [

	^ self returnResultDo: [
			  self
				  executeVariableRefactoring: (RBExtractToTemporaryRefactoring
						   extract: (self intervalFromRefactoringRequest: request)
						   to: (request at: #variable_name)
						   from: (request at: #method_name) asSymbol
						   in: (self classFromRefactoringRequest: request))
				  request: request ]
]

{ #category : 'variable refactoring' }
GenieServer >> handleGenerateLazyVariableAccessor: request [

	^ self returnResultDo: [
			  self
				  executeVariableRefactoring:
					  (RBCreateLazyAccessorsForVariableTransformation
						   variable: (request at: #variable_name)
						   class: (self classFromRefactoringRequest: request)
						   classVariable:
						   (self classVariableFromRefactoringRequest: request)
						   defaultValue: (request at: #default_value))
				  request: request ]
]

{ #category : 'variable refactoring' }
GenieServer >> handleGenerateVariableAccessor: request [

	^ self returnResultDo: [
			  self
				  executeVariableRefactoring:
					  (ReCreateAccessorsForVariableTransformation
						   variable: (request at: #variable_name)
						   class: (self classFromRefactoringRequest: request)
						   classVariable:
						   (self classVariableFromRefactoringRequest: request))
				  request: request ]
]

{ #category : 'variable refactoring' }
GenieServer >> handleGenerateVariableAccessors: request [

	^ self returnResultDo: [
			  self
				  executeGenerateVariableAccessorsFor: request
				  class: (self classFromRefactoringRequest: request)
				  tool: (request at: #tool_name) ]
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

{ #category : 'method refactoring' }
GenieServer >> handleInlineAllSenders: request [

	^ self returnResultDo: [
			  self
				  executeMethodRefactoring: (RBInlineAllSendersRefactoring
						   sendersOf: (request at: #method_name) asSymbol
						   in: (self classFromRefactoringRequest: request))
				  request: request ]
]

{ #category : 'method refactoring' }
GenieServer >> handleInlineMethod: request [

	^ self returnResultDo: [
			  self
				  executeMethodRefactoring: (RBInlineMethodRefactoring
						   inline: (self intervalFromRefactoringRequest: request)
						   inMethod: (request at: #method_name) asSymbol
						   forClass: (self classFromRefactoringRequest: request))
				  request: request ]
]

{ #category : 'method refactoring' }
GenieServer >> handleInlineParameter: request [

	^ self returnResultDo: [
			  self
				  executeMethodRefactoring: (RBInlineParameterRefactoring
						   inlineParameter: (request at: #parameter_name)
						   in: (self classFromRefactoringRequest: request)
						   selector: (request at: #method_name) asSymbol)
				  request: request ]
]

{ #category : 'variable refactoring' }
GenieServer >> handleInlineTemporary: request [

	^ self returnResultDo: [
			  self
				  executeVariableRefactoring: (RBInlineTemporaryRefactoring
						   inline: (self intervalFromRefactoringRequest: request)
						   from: (request at: #method_name) asSymbol
						   in: (self classFromRefactoringRequest: request))
				  request: request ]
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

{ #category : 'variable refactoring' }
GenieServer >> handleMergeInstanceVariable: request [

	^ self returnResultDo: [
			  self
				  executeVariableRefactoring: (RBMergeInstanceVariableIntoAnother
						   rename: (request at: #variable_name)
						   to: (request at: #target_variable_name)
						   in: (self classFromRefactoringRequest: request))
				  request: request ]
]

{ #category : 'method refactoring' }
GenieServer >> handleMoveMethod: request [

	^ self returnResultDo: [
			  | refactoring |
			  refactoring := RBMoveMethodRefactoring
				                 selector: (request at: #method_name) asSymbol
				                 class:
				                 (self classFromRefactoringRequest: request)
				                 variable: (request at: #variable_name).
			  self
				  executeMethodRefactoring:
				  (self
					   configureMethodRefactoringOptions: refactoring
					   request: request)
				  request: request ]
]

{ #category : 'method refactoring' }
GenieServer >> handleMoveMethodToClass: request [

	^ self returnResultDo: [
			  | targetClass selector compiledMethod |
			  targetClass := self classFromRefactoringRequest: request.
			  selector := (request at: #method_name) asSymbol.
			  compiledMethod := self
				                    compiledMethodFor: selector
				                    class: targetClass
				                    classSide:
				                    (request
					                     at: #is_class_method
					                     ifAbsent: [ false ]) == true.
			  self
				  executeMethodRefactoring: (RBMoveMethodToClassRefactoring
						   method: compiledMethod
						   class:
						   (self targetClassFromMethodRefactoringRequest: request))
				  request: request ]
]

{ #category : 'method refactoring' }
GenieServer >> handleMoveMethodToClassSide: request [

	^ self returnResultDo: [
			  | targetClass selector compiledMethod |
			  targetClass := self classFromRefactoringRequest: request.
			  selector := (request at: #method_name) asSymbol.
			  compiledMethod := self
				                    compiledMethodFor: selector
				                    class: targetClass
				                    classSide: false.
			  self
				  executeMethodRefactoring: (RBMoveMethodToClassSideRefactoring
						   method: compiledMethod
						   class: targetClass)
				  request: request ]
]

{ #category : 'method refactoring' }
GenieServer >> handleMoveMethodToInstanceSide: request [

	^ self returnResultDo: [
			  | targetClass selector compiledMethod targetClassName |
			  targetClass := self classFromRefactoringRequest: request.
			  selector := (request at: #method_name) asSymbol.
			  compiledMethod := self
				                    compiledMethodFor: selector
				                    class: targetClass
				                    classSide: true.
			  targetClassName := request
				                     at: #target_class_name
				                     ifAbsent: [ nil ].
			  targetClassName ifNotNil: [
				  targetClass := self targetClassFromMethodRefactoringRequest:
					                 request ].
			  self
				  executeMethodRefactoring: (RBMoveMethodToClassRefactoring
						   method: compiledMethod
						   class: targetClass)
				  request: request ]
]

{ #category : 'variable refactoring' }
GenieServer >> handleMoveVariableDefinitionToSmallestScope: request [

	^ self returnResultDo: [
			  self
				  executeVariableRefactoring:
					  (RBMoveVariableDefinitionToSmallestValidScopeRefactoring
						   bindTight: (self intervalFromRefactoringRequest: request)
						   in: (self classFromRefactoringRequest: request)
						   selector: (request at: #method_name) asSymbol)
				  request: request ]
]

{ #category : 'variable refactoring' }
GenieServer >> handleProtectInstanceVariable: request [

	^ self returnResultDo: [
			  self
				  executeVariableRefactoring:
					  (RBProtectInstanceVariableRefactoring
						   variable: (request at: #variable_name)
						   class: (self classFromRefactoringRequest: request))
				  request: request ]
]

{ #category : 'variable refactoring' }
GenieServer >> handlePullUpClassVariable: request [

	^ self returnResultDo: [
			  | targetClass variableName pullUpTarget |
			  targetClass := self classFromRefactoringRequest: request.
			  variableName := request at: #variable_name.
			  pullUpTarget := self
				                  pullUpTargetFor: targetClass
				                  variable: variableName
				                  classVariable: true.
			  self
				  executeVariableRefactoring: (RBPullUpClassVariableRefactoring
						   variable: variableName
						   class: pullUpTarget)
				  request: request ]
]

{ #category : 'variable refactoring' }
GenieServer >> handlePullUpInstanceVariable: request [

	^ self returnResultDo: [
			  | targetClass variableName pullUpTarget |
			  targetClass := self classFromRefactoringRequest: request.
			  variableName := request at: #variable_name.
			  pullUpTarget := self
				                  pullUpTargetFor: targetClass
				                  variable: variableName
				                  classVariable: false.
			  self
				  executeVariableRefactoring:
					  (RePullUpInstanceVariableRefactoring
						   variable: variableName
						   class: pullUpTarget)
				  request: request ]
]

{ #category : 'method refactoring' }
GenieServer >> handlePullUpMethod: request [

	^ self returnResultDo: [
			  | targetClass selectors targetClassName refactoring |
			  targetClass := self classFromRefactoringRequest: request.
			  selectors := self
				               selectorCollectionFromMethodRefactoringRequest:
				               request.
			  targetClassName := request
				                     at: #target_class_name
				                     ifAbsent: [ nil ].
			  refactoring := targetClassName
				                 ifNil: [
				                 RBPullUpMethodTransformation
					                 pullUp: selectors
					                 from: targetClass ]
				                 ifNotNil: [
						                 RBPullUpMethodTransformation
							                 pullUp: selectors
							                 from: targetClass
							                 to:
							                 (self
								                  targetClassFromMethodRefactoringRequest:
								                  request) ].
			  self executeMethodRefactoring: refactoring request: request ]
]

{ #category : 'variable refactoring' }
GenieServer >> handlePushDownClassVariable: request [

	^ self returnResultDo: [
			  self
				  executeVariableRefactoring: (RBPushDownClassVariableRefactoring
						   variable: (request at: #variable_name)
						   class: (self classFromRefactoringRequest: request))
				  request: request ]
]

{ #category : 'variable refactoring' }
GenieServer >> handlePushDownInstanceVariable: request [

	^ self returnResultDo: [
			  self
				  executeVariableRefactoring:
					  (RBPushDownInstanceVariableRefactoring
						   variable: (request at: #variable_name)
						   class: (self classFromRefactoringRequest: request))
				  request: request ]
]

{ #category : 'handlers - refactoring' }
GenieServer >> handlePushDownMethod: request [

	^ self returnResultDo: [
			  | targetClass selectors targetClassNames refactoring |
			  targetClass := self classFromRefactoringRequest: request.
			  selectors := self
				               selectorCollectionFromMethodRefactoringRequest:
				               request.
			  targetClassNames := request
				                      at: #target_class_names
				                      ifAbsent: [ nil ].
			  refactoring := targetClassNames
				                 ifNil: [
					                 RBPushDownMethodRefactoring
						                 pushDown: selectors
						                 from: targetClass name ]
				                 ifNotNil: [
						                 RBPushDownMethodRefactoring
							                 pushDown: selectors
							                 from: targetClass
							                 in:
							                 (self
								                  targetClassesFromMethodRefactoringRequest:
								                  request) ].
			  self executeMethodRefactoring: refactoring request: request ]
]

{ #category : 'method refactoring' }
GenieServer >> handleRemoveAllMessageSends: request [

	^ self returnResultDo: [
			  | targetClass selector messageSelector |
			  targetClass := self classFromRefactoringRequest: request.
			  selector := (request at: #method_name) asSymbol.
			  messageSelector := self
				                     messageSelectorFromMethodRefactoringRequest:
				                     request.
			  [ self method: selector in: targetClass sends: messageSelector ]
				  whileTrue: [
						  (RBRemoveAllMessageSendsTransformation
							   messageSend: messageSelector
							   inMethod: selector
							   inClass: targetClass name) execute ].
			  self
				  methodRefactoringResultForTool: (request at: #tool_name)
				  request: request ]
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

{ #category : 'variable refactoring' }
GenieServer >> handleRemoveClassVariable: request [

	^ self returnResultDo: [
			  self
				  executeVariableRefactoring: (ReRemoveSharedVariableRefactoring
						   remove: (request at: #variable_name)
						   from: (self classFromRefactoringRequest: request))
				  request: request ]
]

{ #category : 'variable refactoring' }
GenieServer >> handleRemoveInstanceVariable: request [

	^ self returnResultDo: [
			  self
				  executeVariableRefactoring:
					  (ReRemoveInstanceVariableRefactoring
						   remove: (request at: #variable_name)
						   from: (self classFromRefactoringRequest: request))
				  request: request ]
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

{ #category : 'method refactoring' }
GenieServer >> handleRemoveMethodsInHierarchy: request [

	^ self returnResultDo: [
			  self
				  executeMethodRefactoring:
					  (ReRemoveMethodsInHierarchyRefactoring
						   selectors:
						   (self selectorCollectionFromMethodRefactoringRequest: request)
						   from: (self classFromRefactoringRequest: request))
				  request: request ]
]

{ #category : 'method refactoring' }
GenieServer >> handleRemoveParameter: request [

	^ self returnResultDo: [
			  | refactoring |
			  refactoring := RBRemoveParameterRefactoring
				                 removeParameter: (request at: #parameter_name)
				                 in: (self classFromRefactoringRequest: request)
				                 selector: (request at: #method_name) asSymbol.
			  (request at: #new_method_name ifAbsent: [ nil ]) ifNotNil: [
				  :name | refactoring newSelector: name asSymbol ].
			  self executeMethodRefactoring: refactoring request: request ]
]

{ #category : 'variable refactoring' }
GenieServer >> handleRemoveSharedVariable: request [

	^ self returnResultDo: [
			  self
				  executeVariableRefactoring: (ReRemoveSharedVariableRefactoring
						   remove: (request at: #variable_name)
						   from: (self classFromRefactoringRequest: request))
				  request: request ]
]

{ #category : 'variable refactoring' }
GenieServer >> handleRemoveUnusedTemporary: request [

	^ self returnResultDo: [
			  self
				  executeVariableRefactoring:
					  (ReRemoveUnusedTemporaryVariableRefactoring new
						   inMethod: (request at: #method_name) asSymbol
						   inClass: (self classFromRefactoringRequest: request) name;
						   yourself)
				  request: request ]
]

{ #category : 'variable refactoring' }
GenieServer >> handleRenameArgumentOrTemporary: request [

	^ self returnResultDo: [
			  self
				  executeVariableRefactoring:
					  (RBRenameArgumentOrTemporaryRefactoring
						   renameTemporaryFrom:
						   (self intervalFromRefactoringRequest: request)
						   to: (request at: #new_variable_name)
						   in: (self classFromRefactoringRequest: request)
						   selector: (request at: #method_name) asSymbol)
				  request: request ]
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

{ #category : 'variable refactoring' }
GenieServer >> handleRenameClassVariable: request [

	^ self returnResultDo: [
			  self
				  executeVariableRefactoring: (RBRenameVariableTransformation
						   rename: (request at: #variable_name)
						   to: (request at: #new_variable_name)
						   in: (self classFromRefactoringRequest: request)
						   classVariable: true)
				  request: request ]
]

{ #category : 'variable refactoring' }
GenieServer >> handleRenameInstanceVariable: request [

	^ self returnResultDo: [
			  self
				  executeVariableRefactoring:
					  (RBRenameInstanceVariableRefactoring
						   rename: (request at: #variable_name)
						   to: (request at: #new_variable_name)
						   in: (self classFromRefactoringRequest: request)
						   renameAccessors:
						   (request at: #rename_accessors ifAbsent: [ false ]) == true)
				  request: request ]
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

{ #category : 'variable refactoring' }
GenieServer >> handleRenameSharedVariable: request [

	^ self returnResultDo: [
			  self
				  executeVariableRefactoring: (ReRenameSharedVariableRefactoring
						   rename: (request at: #variable_name)
						   to: (request at: #new_variable_name)
						   in: (self classFromRefactoringRequest: request))
				  request: request ]
]

{ #category : 'method refactoring' }
GenieServer >> handleReplaceMessageSend: request [

	^ self returnResultDo: [
			  | messageSelector newSelector permutation inAllClasses |
			  messageSelector := self
				                     messageSelectorFromMethodRefactoringRequest:
				                     request.
			  newSelector := (request
				                  at: #new_message_selector
				                  ifAbsent: [ request at: #new_method_name ])
				                 asSymbol.
			  permutation := self
				                 permutationFromMethodRefactoringRequest: request
				                 oldSelector: messageSelector
				                 newSelector: newSelector.
			  inAllClasses := (request at: #in_all_classes ifAbsent: [ true ])
			                  == true.
			  self
				  executeMethodRefactoring: (RBReplaceMessageSendTransformation
						   replaceCallMethod: messageSelector
						   in: (self classFromRefactoringRequest: request)
						   to: newSelector
						   permutation: permutation
						   inAllClasses: inAllClasses
						   newArgs:
						   (self newArgumentsFromMethodRefactoringRequest: request))
				  request: request ]
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

{ #category : 'method refactoring' }
GenieServer >> handleSplitCascade: request [

	^ self returnResultDo: [
			  self
				  executeMethodRefactoring: (RBSplitCascadeRefactoring
						   split: (self intervalFromRefactoringRequest: request)
						   from: (request at: #method_name) asSymbol
						   in: (self classFromRefactoringRequest: request))
				  request: request ]
]

{ #category : 'variable refactoring' }
GenieServer >> handleTemporaryToInstanceVariable: request [

	^ self returnResultDo: [
			  self
				  executeVariableRefactoring:
					  (RBTemporaryToInstanceVariableTransformation
						   class: (self classFromRefactoringRequest: request)
						   selector: (request at: #method_name) asSymbol
						   variable: (request at: #variable_name))
				  request: request ]
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

{ #category : 'private' }
GenieServer >> intervalFromRefactoringRequest: request [

	^ (request at: #start) asInteger to: (request at: #stop) asInteger
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

{ #category : 'mcp tools' }
GenieServer >> mcpMethodRefactoringTool: aName description: aDescription selector: aSelector properties: properties required: requiredNames [

	^ self
		  mcpTool: aName
		  description: aDescription
		  selector: aSelector
		  properties: properties
		  required: requiredNames
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
	(self allowDangerousTools not and: [
		 self dangerousToolNames includes: toolName ]) ifTrue: [
			^ self
				  jsonRpcError: -32600
				  message:
				  'Tool disabled: ' , toolName , ' (allowDangerousTools is off)'
				  id: anId ].
	arguments := params at: 'arguments' ifAbsent: [ Dictionary new ].
	arguments at: 'tool_name' put: toolName.
	spec := self allMcpToolSpecs
		        detect: [ :s | (s at: 'name') = toolName ]
		        ifNone: [ nil ].
	spec ifNil: [
			^ self
				  jsonRpcError: -32602
				  message: 'Unknown tool: ' , toolName
				  id: anId ].
	result := self
		          perform: (spec at: 'selector')
		          with: (Wish new setArguments: arguments).
	text := String streamContents: [ :s |
		        (NeoJSONWriter on: s) nextPut: result ].
	^ self
		  jsonRpc: {
				  ('content' -> { {
					   ('type' -> 'text').
					   ('text' -> text) } asDictionary }).
				  ('isError' -> (result at: 'success') not) } asDictionary
		  id: anId
]

{ #category : 'mcp - protocol' }
GenieServer >> mcpToolsList: anId [

	| tools |
	tools := self allMcpToolSpecs collect: [ :spec |
			         {
				         ('name' -> (spec at: 'name')).
				         ('description' -> (spec at: 'description')).
				         ('inputSchema' -> (spec at: 'inputSchema')) }
				         asDictionary ].
	^ self jsonRpc: { ('tools' -> tools asArray) } asDictionary id: anId
]

{ #category : 'mcp tools' }
GenieServer >> mcpVariableRefactoringTool: aName description: aDescription selector: aSelector properties: properties required: requiredNames [

	^ self
		  mcpTool: aName
		  description: aDescription
		  selector: aSelector
		  properties: properties
		  required: requiredNames
]

{ #category : 'method refactoring' }
GenieServer >> messageSelectorFromMethodRefactoringRequest: request [

	^ (request at: #message_selector ifAbsent: [
			   request
				   at: #old_message_selector
				   ifAbsent: [ request at: #method_name ] ]) asSymbol
]

{ #category : 'method refactoring' }
GenieServer >> method: selector in: targetClass sends: messageSelector [

	| parseTree |
	parseTree := targetClass parseTreeForSelector: selector.
	parseTree ifNil: [
		self error: 'Could not parse source for ' , selector ].
	^ parseTree allChildren anySatisfy: [ :each |
		  each isMessage and: [ each selector = messageSelector ] ]
]

{ #category : 'method refactoring' }
GenieServer >> methodRefactoringResultForTool: toolName request: request [

	| result |
	result := Dictionary new.
	result at: 'tool' put: toolName.
	#( 'class_name' 'target_class_name' 'method_name' 'new_method_name'
	   'message_selector' 'old_message_selector' 'new_message_selector'
	   'variable_name' 'parameter_name' 'new_parameter_name' ) do: [ :key |
			| value |
			value := request at: key ifAbsent: [ nil ].
			value ifNotNil: [ result at: key put: value ] ].
	(request at: #method_names ifAbsent: [ nil ]) ifNotNil: [ :names |
		result at: 'method_names' put: names asArray ].
	(request at: #target_class_names ifAbsent: [ nil ]) ifNotNil: [
		:names | result at: 'target_class_names' put: names asArray ].
	^ result
]

{ #category : 'mcp tools' }
GenieServer >> methodRefactoringToolSpecs [

	^ {
		  (self
			   mcpMethodRefactoringTool: 'extract_method'
			   description:
			   'Extract the selected source interval into a new method.'
			   selector: #handleExtractMethod:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string').
					   ('new_method_name' -> 'string').
					   ('argument_names' -> 'array').
					   ('start' -> 'integer').
					   ('stop' -> 'integer') }
			   required:
			   #( 'class_name' 'method_name' 'new_method_name'
			      'start' 'stop' )).
		  (self
			   mcpMethodRefactoringTool: 'extract_method_and_occurrences'
			   description:
			   'Extract the selected source interval and matching occurrences into a new method.'
			   selector: #handleExtractMethodAndOccurrences:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string').
					   ('new_method_name' -> 'string').
					   ('argument_names' -> 'array').
					   ('start' -> 'integer').
					   ('stop' -> 'integer') }
			   required:
			   #( 'class_name' 'method_name' 'new_method_name'
			      'start' 'stop' )).
		  (self
			   mcpMethodRefactoringTool: 'extract_method_to_component'
			   description:
			   'Extract the selected source interval, move the new method to a component, and inline the forwarder.'
			   selector: #handleExtractMethodToComponent:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string').
					   ('new_method_name' -> 'string').
					   ('argument_names' -> 'array').
					   ('variable_name' -> 'string').
					   ('start' -> 'integer').
					   ('stop' -> 'integer') }
			   required:
				   #( 'class_name' 'method_name' 'new_method_name'
				      'variable_name' 'start' 'stop' )).
		  (self
			   mcpMethodRefactoringTool: 'extract_setup_method'
			   description: 'Extract the selected setup statements to setUp.'
			   selector: #handleExtractSetupMethod:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string').
					   ('start' -> 'integer').
					   ('stop' -> 'integer') }
			   required: #( 'class_name' 'method_name' 'start' 'stop' )).
		  (self
			   mcpMethodRefactoringTool: 'extract_setup_method_and_occurrences'
			   description:
			   'Extract the selected setup statements and matching occurrences to setUp.'
			   selector: #handleExtractSetupMethodAndOccurrences:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string').
					   ('start' -> 'integer').
					   ('stop' -> 'integer') }
			   required: #( 'class_name' 'method_name' 'start' 'stop' )).
		  (self
			   mcpMethodRefactoringTool: 'inline_method'
			   description: 'Inline the selected message send in a method.'
			   selector: #handleInlineMethod:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string').
					   ('start' -> 'integer').
					   ('stop' -> 'integer') }
			   required: #( 'class_name' 'method_name' 'start' 'stop' )).
		  (self
			   mcpMethodRefactoringTool: 'inline_all_senders'
			   description: 'Inline all senders of a method.'
			   selector: #handleInlineAllSenders:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string') }
			   required: #( 'class_name' 'method_name' )).
		  (self
			   mcpMethodRefactoringTool: 'move_method'
			   description:
			   'Move a method to the class indicated by a variable, argument, or class reference.'
			   selector: #handleMoveMethod:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string').
					   ('variable_name' -> 'string').
					   ('new_method_name' -> 'string').
					   ('argument_names' -> 'array').
					   ('self_argument_name' -> 'string').
					   ('variable_type_names' -> 'array') }
			   required: #( 'class_name' 'method_name' 'variable_name' )).
		  (self
			   mcpMethodRefactoringTool: 'move_method_to_class'
			   description:
			   'Move an instance-side or class-side method to another class.'
			   selector: #handleMoveMethodToClass:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string').
					   ('target_class_name' -> 'string').
					   ('is_class_method' -> 'boolean') }
			   required: #( 'class_name' 'method_name' 'target_class_name' )).
		  (self
			   mcpMethodRefactoringTool: 'move_method_to_class_side'
			   description: 'Move an instance-side method to its class side.'
			   selector: #handleMoveMethodToClassSide:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string') }
			   required: #( 'class_name' 'method_name' )).
		  (self
			   mcpMethodRefactoringTool: 'move_method_to_instance_side'
			   description: 'Move a class-side method to an instance side.'
			   selector: #handleMoveMethodToInstanceSide:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string').
					   ('target_class_name' -> 'string') }
			   required: #( 'class_name' 'method_name' )).
		  (self
			   mcpMethodRefactoringTool: 'pull_up_method'
			   description:
			   'Pull one or more methods from a subclass to a superclass.'
			   selector: #handlePullUpMethod:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string').
					   ('method_names' -> 'array').
					   ('target_class_name' -> 'string') }
			   required: #( 'class_name' 'method_name' )).
		  (self
			   mcpMethodRefactoringTool: 'push_down_method'
			   description:
			   'Push one or more methods from a superclass to subclasses.'
			   selector: #handlePushDownMethod:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string').
					   ('method_names' -> 'array').
					   ('target_class_names' -> 'array') }
			   required: #( 'class_name' 'method_name' )).
		  (self
			   mcpMethodRefactoringTool: 'remove_methods_in_hierarchy'
			   description: 'Remove methods from a class and its subclasses.'
			   selector: #handleRemoveMethodsInHierarchy:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string').
					   ('method_names' -> 'array') }
			   required: #( 'class_name' 'method_name' )).
		  (self
			   mcpMethodRefactoringTool: 'add_parameter'
			   description: 'Add a parameter to a method and update senders.'
			   selector: #handleAddParameter:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string').
					   ('new_method_name' -> 'string').
					   ('parameter_name' -> 'string').
					   ('default_value' -> 'string').
					   ('new_arguments' -> 'array').
					   ('permutation' -> 'array') }
			   required:
				   #( 'class_name' 'method_name' 'new_method_name'
				      'parameter_name' 'default_value' )).
		  (self
			   mcpMethodRefactoringTool: 'remove_parameter'
			   description:
			   'Remove an unused parameter from a method and update senders.'
			   selector: #handleRemoveParameter:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string').
					   ('parameter_name' -> 'string').
					   ('new_method_name' -> 'string') }
			   required: #( 'class_name' 'method_name' 'parameter_name' )).
		  (self
			   mcpMethodRefactoringTool: 'inline_parameter'
			   description:
			   'Inline a parameter whose senders all pass the same literal value.'
			   selector: #handleInlineParameter:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string').
					   ('parameter_name' -> 'string') }
			   required: #( 'class_name' 'method_name' 'parameter_name' )).
		  (self
			   mcpMethodRefactoringTool: 'change_method_signature'
			   description:
			   'Rename a method selector and optionally permute arguments while updating senders.'
			   selector: #handleChangeMethodSignature:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string').
					   ('new_method_name' -> 'string').
					   ('permutation' -> 'array') }
			   required: #( 'class_name' 'method_name' 'new_method_name' )).
		  (self
			   mcpMethodRefactoringTool: 'deprecate_method'
			   description:
			   'Insert a deprecation notice at the start of a method.'
			   selector: #handleDeprecateMethod:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string').
					   ('new_method_name' -> 'string') }
			   required: #( 'class_name' 'method_name' 'new_method_name' )).
		  (self
			   mcpMethodRefactoringTool: 'replace_message_send'
			   description:
			   'Replace message sends of one selector with another selector.'
			   selector: #handleReplaceMessageSend:
			   properties: {
					   ('class_name' -> 'string').
					   ('message_selector' -> 'string').
					   ('old_message_selector' -> 'string').
					   ('new_message_selector' -> 'string').
					   ('new_method_name' -> 'string').
					   ('new_arguments' -> 'array').
					   ('permutation' -> 'array').
					   ('in_all_classes' -> 'boolean') }
			   required:
			   #( 'class_name' 'message_selector' 'new_message_selector' )).
		  (self
			   mcpMethodRefactoringTool: 'remove_all_message_sends'
			   description:
			   'Remove all message sends of a selector inside one method.'
			   selector: #handleRemoveAllMessageSends:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string').
					   ('message_selector' -> 'string') }
			   required: #( 'class_name' 'method_name' 'message_selector' )).
		  (self
			   mcpMethodRefactoringTool: 'create_cascade'
			   description:
			   'Create a cascade from selected consecutive message sends.'
			   selector: #handleCreateCascade:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string').
					   ('start' -> 'integer').
					   ('stop' -> 'integer') }
			   required: #( 'class_name' 'method_name' 'start' 'stop' )).
		  (self
			   mcpMethodRefactoringTool: 'split_cascade'
			   description: 'Split a cascade at the selected boundary.'
			   selector: #handleSplitCascade:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string').
					   ('start' -> 'integer').
					   ('stop' -> 'integer') }
			   required: #( 'class_name' 'method_name' 'start' 'stop' )) }
]

{ #category : 'method refactoring' }
GenieServer >> newArgumentsFromMethodRefactoringRequest: request [

	| entries parameterName defaultValue |
	entries := request at: #new_arguments ifAbsent: [ nil ].
	entries ifNotNil: [
			^ entries collect: [ :entry |
					  | argumentName argumentValue |
					  argumentName := entry at: 'name' ifAbsent: [ entry at: #name ].
					  argumentValue := entry
						                   at: 'value'
						                   ifAbsent: [
						                   entry
							                   at: 'default_value'
							                   ifAbsent: [ entry at: #default_value ] ].
					  RBArgumentName name: argumentName value: argumentValue ] ].
	parameterName := request
		                 at: #parameter_name
		                 ifAbsent: [
		                 request at: #new_parameter_name ifAbsent: [ nil ] ].
	parameterName ifNil: [ ^ #(  ) ].
	defaultValue := request at: #default_value ifAbsent: [ 'nil' ].
	^ { (RBArgumentName name: parameterName value: defaultValue) }
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

{ #category : 'method refactoring' }
GenieServer >> permutationFromMethodRefactoringRequest: request oldSelector: oldSelector newSelector: newSelector [

	| supplied oldArgumentCount newArgumentCount result |
	supplied := request at: #permutation ifAbsent: [ nil ].
	supplied ifNotNil: [ ^ supplied collect: [ :each | each asInteger ] ].
	oldArgumentCount := oldSelector numArgs.
	newArgumentCount := newSelector numArgs.
	result := OrderedCollection new.
	1 to: (oldArgumentCount min: newArgumentCount) do: [ :index |
	result add: index ].
	newArgumentCount > oldArgumentCount ifTrue: [
			1 to: newArgumentCount - oldArgumentCount do: [ :index |
			result add: index negated ] ].
	^ result asArray
]

{ #category : 'private - refactoring' }
GenieServer >> pullUpTargetFor: aClass variable: variableName classVariable: classVariable [

	| directlyDefinesVariable targetClass |
	directlyDefinesVariable := classVariable
		                           ifTrue: [
				                           aClass classVarNames anySatisfy: [
					                           :each | each asString = variableName ] ]
		                           ifFalse: [
				                           aClass instVarNames anySatisfy: [ :each |
					                           each asString = variableName ] ].
	directlyDefinesVariable ifFalse: [ ^ aClass ].
	targetClass := aClass superclass.
	targetClass ifNil: [
			self error:
				'Cannot pull up ' , variableName , ' from ' , aClass name
				, ': no superclass' ].
	^ targetClass
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

{ #category : 'method refactoring' }
GenieServer >> selectorCollectionFromMethodRefactoringRequest: request [

	| selectorNames selectorName |
	selectorNames := request at: #method_names ifAbsent: [ nil ].
	selectorNames ifNotNil: [
		^ selectorNames collect: [ :each | each asSymbol ] ].
	selectorName := request at: #method_name.
	^ { selectorName asSymbol }
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

{ #category : 'method refactoring' }
GenieServer >> targetClassFromMethodRefactoringRequest: request [

	| className targetClass |
	className := request at: #target_class_name.
	targetClass := Smalltalk classNamed: className.
	targetClass ifNil: [
		self error: 'Unknown target class: ' , className ].
	^ targetClass
]

{ #category : 'method refactoring' }
GenieServer >> targetClassesFromMethodRefactoringRequest: request [

	| classNames |
	classNames := request at: #target_class_names.
	^ classNames collect: [ :className |
			  | targetClass |
			  targetClass := Smalltalk classNamed: className.
			  targetClass ifNil: [
				  self error: 'Unknown target class: ' , className ].
			  targetClass ]
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

{ #category : 'private' }
GenieServer >> variableRefactoringResultForTool: toolName request: request variables: variableNames [

	| result |
	result := Dictionary new.
	result at: 'tool' put: toolName.
	#( 'class_name' 'method_name' 'variable_name' 'new_variable_name'
	   'target_variable_name' ) do: [ :key |
			| value |
			value := request at: key ifAbsent: [ nil ].
			value ifNotNil: [ result at: key put: value ] ].
	variableNames ifNotNil: [
		result at: 'variable_names' put: variableNames asArray ].
	^ result
]

{ #category : 'mcp tools' }
GenieServer >> variableRefactoringToolSpecs [

	^ {
		  (self
			   mcpVariableRefactoringTool: 'add_instance_variable'
			   description: 'Add an instance variable to a class.'
			   selector: #handleAddInstanceVariable:
			   properties: {
					   ('class_name' -> 'string').
					   ('variable_name' -> 'string') }
			   required: #( 'class_name' 'variable_name' )).
		  (self
			   mcpVariableRefactoringTool: 'remove_instance_variable'
			   description: 'Remove an instance variable from a class.'
			   selector: #handleRemoveInstanceVariable:
			   properties: {
					   ('class_name' -> 'string').
					   ('variable_name' -> 'string') }
			   required: #( 'class_name' 'variable_name' )).
		  (self
			   mcpVariableRefactoringTool: 'rename_instance_variable'
			   description:
			   'Rename an instance variable and update references.'
			   selector: #handleRenameInstanceVariable:
			   properties: {
					   ('class_name' -> 'string').
					   ('variable_name' -> 'string').
					   ('new_variable_name' -> 'string').
					   ('rename_accessors' -> 'boolean') }
			   required: #( 'class_name' 'variable_name' 'new_variable_name' )).
		  (self
			   mcpVariableRefactoringTool: 'pull_up_instance_variable'
			   description:
			   'Pull an instance variable from a subclass to its superclass.'
			   selector: #handlePullUpInstanceVariable:
			   properties: {
					   ('class_name' -> 'string').
					   ('variable_name' -> 'string') }
			   required: #( 'class_name' 'variable_name' )).
		  (self
			   mcpVariableRefactoringTool: 'push_down_instance_variable'
			   description:
			   'Push an instance variable from a superclass to subclasses.'
			   selector: #handlePushDownInstanceVariable:
			   properties: {
					   ('class_name' -> 'string').
					   ('variable_name' -> 'string') }
			   required: #( 'class_name' 'variable_name' )).
		  (self
			   mcpVariableRefactoringTool: 'add_class_variable'
			   description: 'Add a class variable to a class.'
			   selector: #handleAddClassVariable:
			   properties: {
					   ('class_name' -> 'string').
					   ('variable_name' -> 'string') }
			   required: #( 'class_name' 'variable_name' )).
		  (self
			   mcpVariableRefactoringTool: 'remove_class_variable'
			   description: 'Remove a class variable from a class.'
			   selector: #handleRemoveClassVariable:
			   properties: {
					   ('class_name' -> 'string').
					   ('variable_name' -> 'string') }
			   required: #( 'class_name' 'variable_name' )).
		  (self
			   mcpVariableRefactoringTool: 'rename_class_variable'
			   description: 'Rename a class variable and update references.'
			   selector: #handleRenameClassVariable:
			   properties: {
					   ('class_name' -> 'string').
					   ('variable_name' -> 'string').
					   ('new_variable_name' -> 'string') }
			   required: #( 'class_name' 'variable_name' 'new_variable_name' )).
		  (self
			   mcpVariableRefactoringTool: 'pull_up_class_variable'
			   description:
			   'Pull a class variable from a subclass to its superclass.'
			   selector: #handlePullUpClassVariable:
			   properties: {
					   ('class_name' -> 'string').
					   ('variable_name' -> 'string') }
			   required: #( 'class_name' 'variable_name' )).
		  (self
			   mcpVariableRefactoringTool: 'push_down_class_variable'
			   description:
			   'Push a class variable from a superclass to subclasses.'
			   selector: #handlePushDownClassVariable:
			   properties: {
					   ('class_name' -> 'string').
					   ('variable_name' -> 'string') }
			   required: #( 'class_name' 'variable_name' )).
		  (self
			   mcpVariableRefactoringTool: 'rename_shared_variable'
			   description: 'Rename a shared variable and update references.'
			   selector: #handleRenameSharedVariable:
			   properties: {
					   ('class_name' -> 'string').
					   ('variable_name' -> 'string').
					   ('new_variable_name' -> 'string') }
			   required: #( 'class_name' 'variable_name' 'new_variable_name' )).
		  (self
			   mcpVariableRefactoringTool: 'remove_shared_variable'
			   description: 'Remove a shared variable from a class.'
			   selector: #handleRemoveSharedVariable:
			   properties: {
					   ('class_name' -> 'string').
					   ('variable_name' -> 'string') }
			   required: #( 'class_name' 'variable_name' )).
		  (self
			   mcpVariableRefactoringTool: 'merge_instance_variable'
			   description:
			   'Merge one instance variable into another instance variable.'
			   selector: #handleMergeInstanceVariable:
			   properties: {
					   ('class_name' -> 'string').
					   ('variable_name' -> 'string').
					   ('target_variable_name' -> 'string') }
			   required:
			   #( 'class_name' 'variable_name' 'target_variable_name' )).
		  (self
			   mcpVariableRefactoringTool: 'protect_instance_variable'
			   description:
			   'Protect an instance variable by inlining direct accessor references.'
			   selector: #handleProtectInstanceVariable:
			   properties: {
					   ('class_name' -> 'string').
					   ('variable_name' -> 'string') }
			   required: #( 'class_name' 'variable_name' )).
		  (self
			   mcpVariableRefactoringTool: 'generate_variable_accessor'
			   description:
			   'Generate accessor methods for one instance or class variable.'
			   selector: #handleGenerateVariableAccessor:
			   properties: {
					   ('class_name' -> 'string').
					   ('variable_name' -> 'string').
					   ('class_variable' -> 'boolean') }
			   required: #( 'class_name' 'variable_name' )).
		  (self
			   mcpVariableRefactoringTool: 'generate_variable_accessors'
			   description:
			   'Generate accessor methods for all or selected instance/class variables.'
			   selector: #handleGenerateVariableAccessors:
			   properties: {
					   ('class_name' -> 'string').
					   ('class_variable' -> 'boolean').
					   ('variable_names' -> 'array') }
			   required: #( 'class_name' )).
		  (self
			   mcpVariableRefactoringTool: 'generate_lazy_variable_accessor'
			   description:
			   'Generate a lazy-initializing accessor for one instance or class variable.'
			   selector: #handleGenerateLazyVariableAccessor:
			   properties: {
					   ('class_name' -> 'string').
					   ('variable_name' -> 'string').
					   ('class_variable' -> 'boolean').
					   ('default_value' -> 'string') }
			   required: #( 'class_name' 'variable_name' 'default_value' )).
		  (self
			   mcpVariableRefactoringTool: 'temporary_to_instance_variable'
			   description:
			   'Convert a temporary variable in a method to an instance variable.'
			   selector: #handleTemporaryToInstanceVariable:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string').
					   ('variable_name' -> 'string') }
			   required: #( 'class_name' 'method_name' 'variable_name' )).
		  (self
			   mcpVariableRefactoringTool: 'extract_temporary'
			   description:
			   'Extract a selected expression to a temporary variable. Uses 1-based start/stop source indexes.'
			   selector: #handleExtractTemporary:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string').
					   ('variable_name' -> 'string').
					   ('start' -> 'integer').
					   ('stop' -> 'integer') }
			   required:
			   #( 'class_name' 'method_name' 'variable_name' 'start' 'stop' )).
		  (self
			   mcpVariableRefactoringTool: 'inline_temporary'
			   description:
			   'Inline a selected temporary variable. Uses 1-based start/stop source indexes.'
			   selector: #handleInlineTemporary:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string').
					   ('start' -> 'integer').
					   ('stop' -> 'integer') }
			   required: #( 'class_name' 'method_name' 'start' 'stop' )).
		  (self
			   mcpVariableRefactoringTool: 'rename_argument_or_temporary'
			   description:
			   'Rename an argument or temporary selected by 1-based start/stop source indexes.'
			   selector: #handleRenameArgumentOrTemporary:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string').
					   ('new_variable_name' -> 'string').
					   ('start' -> 'integer').
					   ('stop' -> 'integer') }
			   required:
			   #( 'class_name' 'method_name' 'new_variable_name'
			      'start' 'stop' )).
		  (self
			   mcpVariableRefactoringTool: 'remove_unused_temporary'
			   description: 'Remove unused temporary variables from a method.'
			   selector: #handleRemoveUnusedTemporary:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string') }
			   required: #( 'class_name' 'method_name' )).
		  (self
			   mcpVariableRefactoringTool:
			   'move_variable_definition_to_smallest_scope'
			   description:
			   'Move a selected variable definition to its smallest valid scope. Uses 1-based start/stop source indexes.'
			   selector: #handleMoveVariableDefinitionToSmallestScope:
			   properties: {
					   ('class_name' -> 'string').
					   ('method_name' -> 'string').
					   ('start' -> 'integer').
					   ('stop' -> 'integer') }
			   required: #( 'class_name' 'method_name' 'start' 'stop' )) }
]
