//
//  ItemResponse.swift
//  Zotero
//
//  Created by Michal Rentka on 08/02/2019.
//  Copyright © 2019 Corporation for Digital Scholarship. All rights reserved.
//

import Foundation

import CocoaLumberjackSwift

struct ItemResponse {
    let rawType: String
    let key: String
    let library: LibraryResponse
    let parentKey: String?
    let collectionKeys: Set<String>
    let links: LinksResponse?
    let parsedDate: String?
    let isTrash: Bool
    let version: Int
    let dateModified: Date
    let dateAdded: Date
    let fields: [String: String]
    let tags: [TagResponse]
    let creators: [CreatorResponse]
    let relations: [String: Any]
    let inPublications: Bool
    let createdBy: UserResponse?
    let lastModifiedBy: UserResponse?
    let rects: [[Double]]?
    let paths: [[Double]]?

    init(rawType: String, key: String, library: LibraryResponse, parentKey: String?, collectionKeys: Set<String>, links: LinksResponse?, parsedDate: String?, isTrash: Bool, version: Int,
         dateModified: Date, dateAdded: Date, fields: [String: String], tags: [TagResponse], creators: [CreatorResponse], relations: [String: Any], createdBy: UserResponse?,
         lastModifiedBy: UserResponse?, rects: [[Double]]?, paths: [[Double]]?) {
        self.rawType = rawType
        self.key = key
        self.library = library
        self.parentKey = parentKey
        self.collectionKeys = collectionKeys
        self.links = links
        self.parsedDate = parsedDate
        self.isTrash = isTrash
        self.version = version
        self.dateModified = dateModified
        self.dateAdded = dateAdded
        self.fields = fields
        self.tags = tags
        self.creators = creators
        self.relations = relations
        self.inPublications = false
        self.createdBy = createdBy
        self.lastModifiedBy = lastModifiedBy
        self.rects = rects
        self.paths = paths
    }

    init(response: [String: Any], schemaController: SchemaController) throws {
        let data: [String: Any] = try response.apiGet(key: "data")
        let key: String = try response.apiGet(key: "key")
        let itemType: String = try data.apiGet(key: "itemType")

        if !schemaController.itemTypes.contains(itemType) {
            throw SchemaError.invalidValue(value: itemType, field: "itemType", key: key)
        }

        let library = try LibraryResponse(response: (try response.apiGet(key: "library")))
        let linksData = response["links"] as? [String: Any]
        let links = try linksData.flatMap { try LinksResponse(response: $0) }
        let meta = response["meta"] as? [String: Any]
        let parsedDate = meta?["parsedDate"] as? String
        let createdByData = meta?["createdByUser"] as? [String: Any]
        let createdBy = try createdByData.flatMap { try UserResponse(response: $0) }
        let lastModifiedByData = meta?["lastModifiedByUser"] as? [String: Any]
        let lastModifiedBy = try lastModifiedByData.flatMap { try UserResponse(response: $0) }
        let version: Int = try response.apiGet(key: "version")

        switch itemType {
        case ItemTypes.annotation:
            try self.init(key: key, library: library, links: links, parsedDate: parsedDate, createdBy: createdBy, lastModifiedBy: lastModifiedBy, version: version, annotationData: data,
                          schemaController: schemaController)
        default:
            try self.init(key: key, rawType: itemType, library: library, links: links, parsedDate: parsedDate, createdBy: createdBy, lastModifiedBy: lastModifiedBy, version: version, data: data,
                          schemaController: schemaController)
        }
    }

    // Init any item type except annotation
    private init(key: String, rawType: String, library: LibraryResponse, links: LinksResponse?, parsedDate: String?, createdBy: UserResponse?, lastModifiedBy: UserResponse?, version: Int,
                 data: [String: Any], schemaController: SchemaController) throws {
        let dateAdded = data["dateAdded"] as? String
        let dateModified = data["dateModified"] as? String
        let tags = (data["tags"] as? [[String: Any]]) ?? []
        let creators = (data["creators"] as? [[String: Any]]) ?? []

        self.rawType = rawType
        self.key = key
        self.version = version
        self.collectionKeys = (data["collections"] as? [String]).flatMap(Set.init) ?? []
        self.parentKey = data["parentItem"] as? String
        self.dateAdded = dateAdded.flatMap({ Formatter.iso8601.date(from: $0) }) ?? Date()
        self.dateModified = dateModified.flatMap({ Formatter.iso8601.date(from: $0) }) ?? Date()
        self.parsedDate = parsedDate
        self.isTrash = (data["deleted"] as? Bool) ?? ((data["deleted"] as? Int) == 1)
        self.library = library
        self.links = links
        self.tags = try tags.map({ try TagResponse(response: $0) })
        self.creators = try creators.map({ try CreatorResponse(response: $0) })
        self.relations = (data["relations"] as? [String: Any]) ?? [:]
        self.inPublications = (data["inPublications"] as? Bool) ?? ((data["inPublications"] as? Int) == 1)
        self.fields = try ItemResponse.parseFields(from: data, rawType: rawType, key: key, schemaController: schemaController).fields
        self.createdBy = createdBy
        self.lastModifiedBy = lastModifiedBy
        self.rects = nil
        self.paths = nil

        // Attachment with link mode "embedded_image" always needs a parent assigned
        if rawType == ItemTypes.attachment,
           let linkMode = self.fields[FieldKeys.Item.Attachment.linkMode].flatMap({ LinkMode(rawValue: $0) }),
           linkMode == .embeddedImage && self.parentKey == nil {
            throw SchemaError.embeddedImageMissingParent(key: key, libraryId: library.libraryId ?? .custom(.myLibrary))
        }
    }

    // Init annotation
    private init(key: String, library: LibraryResponse, links: LinksResponse?, parsedDate: String?, createdBy: UserResponse?, lastModifiedBy: UserResponse?, version: Int,
                 annotationData data: [String: Any], schemaController: SchemaController) throws {
        let dateAdded = data["dateAdded"] as? String
        let dateModified = data["dateModified"] as? String
        let tags = (data["tags"] as? [[String: Any]]) ?? []

        let (fields, rects, paths) = try ItemResponse.parseFields(from: data, rawType: ItemTypes.annotation, key: key, schemaController: schemaController)

        self.rawType = ItemTypes.annotation
        self.key = key
        self.version = version
        self.collectionKeys = []
        self.parentKey = try data.apiGet(key: "parentItem")
        self.dateAdded = dateAdded.flatMap({ Formatter.iso8601.date(from: $0) }) ?? Date()
        self.dateModified = dateModified.flatMap({ Formatter.iso8601.date(from: $0) }) ?? Date()
        self.parsedDate = parsedDate
        self.isTrash = (data["deleted"] as? Bool) ?? ((data["deleted"] as? Int) == 1)
        self.library = library
        self.links = links
        self.tags = try tags.map({ try TagResponse(response: $0) })
        self.creators = []
        self.relations = [:]
        self.inPublications = false
        self.fields = fields
        self.createdBy = createdBy
        self.lastModifiedBy = lastModifiedBy
        self.rects = rects
        self.paths = paths
    }

    init(translatorResponse response: [String: Any], schemaController: SchemaController) throws {
        let key = KeyGenerator.newKey
        let rawType: String = try response.apiGet(key: "itemType")
        let accessDate = (response["accessDate"] as? String).flatMap({ Formatter.iso8601.date(from: $0) }) ?? Date()
        let tags = (response["tags"] as? [[String: Any]]) ?? []
        let creators = (response["creators"] as? [[String: Any]]) ?? []

        self.rawType = rawType
        self.key = key
        self.version = 0
        self.collectionKeys = []
        self.parentKey = nil
        self.dateAdded = accessDate
        self.dateModified = accessDate
        self.parsedDate = response["date"] as? String
        self.isTrash = false
        // We create a dummy library here, it's not returned by translation server, it'll be picked in the share extension
        self.library = LibraryResponse(id: 0, name: "", type: "", links: nil)
        self.links = nil
        self.tags = try tags.map({ try TagResponse(response: $0) })
        self.creators = try creators.map({ try CreatorResponse(response: $0) })
        self.relations = [:]
        self.inPublications = false
        // Translator returns some extra fields, which may not be recognized by schema, so we just ignore those
        self.fields = try ItemResponse.parseFields(from: response, rawType: rawType, key: key, schemaController: schemaController, ignoreUnknownFields: true).fields
        self.createdBy = nil
        self.lastModifiedBy = nil
        self.rects = nil
        self.paths = nil
    }

    func copy(libraryId: LibraryIdentifier, collectionKeys: Set<String>, addedTags: [TagResponse]) -> ItemResponse {
        let tags = addedTags.isEmpty ? self.tags : (self.tags + addedTags)
        return ItemResponse(rawType: self.rawType,
                            key: self.key,
                            library: LibraryResponse(libraryId: libraryId),
                            parentKey: self.parentKey,
                            collectionKeys: collectionKeys,
                            links: self.links,
                            parsedDate: self.parsedDate,
                            isTrash: self.isTrash,
                            version: self.version,
                            dateModified: self.dateModified,
                            dateAdded: self.dateAdded,
                            fields: self.fields,
                            tags: tags,
                            creators: self.creators,
                            relations: self.relations,
                            createdBy: self.createdBy,
                            lastModifiedBy: self.lastModifiedBy,
                            rects: self.rects,
                            paths: self.paths)
    }

    var copyWithoutTags: ItemResponse {
        return ItemResponse(rawType: self.rawType,
                            key: self.key,
                            library: self.library,
                            parentKey: self.parentKey,
                            collectionKeys: self.collectionKeys,
                            links: self.links,
                            parsedDate: self.parsedDate,
                            isTrash: self.isTrash,
                            version: self.version,
                            dateModified: self.dateModified,
                            dateAdded: self.dateAdded,
                            fields: self.fields,
                            tags: [],
                            creators: self.creators,
                            relations: self.relations,
                            createdBy: self.createdBy,
                            lastModifiedBy: self.lastModifiedBy,
                            rects: self.rects,
                            paths: self.paths)
    }

    var copyWithAutomaticTags: ItemResponse {
        return ItemResponse(rawType: self.rawType,
                            key: self.key,
                            library: self.library,
                            parentKey: self.parentKey,
                            collectionKeys: self.collectionKeys,
                            links: self.links,
                            parsedDate: self.parsedDate,
                            isTrash: self.isTrash,
                            version: self.version,
                            dateModified: self.dateModified,
                            dateAdded: self.dateAdded,
                            fields: self.fields,
                            tags: self.tags.map({ $0.automaticCopy }),
                            creators: self.creators,
                            relations: self.relations,
                            createdBy: self.createdBy,
                            lastModifiedBy: self.lastModifiedBy,
                            rects: self.rects,
                            paths: self.paths)
    }

    /// Parses field values from item data for given type.
    /// - parameter data: Data to parse.
    /// - parameter rawType: Raw item type of parsed item.
    /// - parameter schemaController: Schema controller to check fields against schema.
    /// - parameter key: Key of item.
    /// - parameter ignoreUnknownFields: If set to `false`, when an unknown field is encountered during parsing, an exception `Error.unknownField` is thrown. Otherwise the field is silently ignored and parsing continues.
    /// - returns: Parsed dictionary of fields with their values.
    private static func parseFields(from data: [String: Any], rawType: String, key: String, schemaController: SchemaController,
                                    ignoreUnknownFields: Bool = false) throws -> (fields: [String: String], rects: [[Double]]?, paths: [[Double]]?) {
        let excludedKeys = FieldKeys.Item.knownNonFieldKeys
        var fields: [String: String] = [:]
        var rects: [[Double]]?
        var paths: [[Double]]?

        guard let schemaFields = schemaController.fields(for: rawType) else { throw SchemaError.missingSchemaFields(itemType: rawType) }

        for object in data {
            guard !excludedKeys.contains(object.key) else { continue }

            if !self.isKnownField(object.key, in: schemaFields, itemType: rawType) {
                if ignoreUnknownFields {
                    continue
                }
                throw SchemaError.unknownField(key: key, field: object.key)
            }

            var value: String
            if let val = object.value as? String {
                value = val
            } else {
                value = "\(object.value)"
            }

            switch object.key {
            case FieldKeys.Item.Annotation.position:
                // Annotations have `annotationPosition` which is a JSON string, so the string needs to be decoded and stored as proper field values
                let (pageIndex, newRects, newPaths, lineWidth) = try self.parsePosition(from: value, key: key)
                rects = newRects
                paths = newPaths
                fields[FieldKeys.Item.Annotation.pageIndex] = "\(pageIndex)"
                if let lineWidth = lineWidth {
                    fields[FieldKeys.Item.Annotation.lineWidth] = "\(lineWidth.rounded(to: 3))"
                }
            case FieldKeys.Item.accessDate:
                if value == "CURRENT_TIMESTAMP" {
                    value = Formatter.iso8601.string(from: Date())
                }
                fields[object.key] = value
            default:
                fields[object.key] = value
            }
        }

        try self.validate(fields: fields, itemType: rawType, key: key)

        return (fields, rects, paths)
    }

    private static func validate(fields: [String: String], itemType: String, key: String) throws {
        switch itemType {
        case ItemTypes.annotation:
            // `position` parameters are validated in `parsePosition(from:key:)` where we have access to their original `String` value.
            guard let rawType = fields[FieldKeys.Item.Annotation.type] else {
                throw SchemaError.missingField(key: key, field: FieldKeys.Item.Annotation.type, itemType: itemType)
            }
            guard let type = AnnotationType(rawValue: rawType) else {
                throw SchemaError.invalidValue(value: rawType, field: FieldKeys.Item.Annotation.type, key: key)
            }

            let mandatoryFields = FieldKeys.Item.Annotation.fields(for: type)
            for field in mandatoryFields {
                guard let value = fields[field] else {
                    throw SchemaError.missingField(key: key, field: field, itemType: itemType)
                }

                switch field {
                case FieldKeys.Item.Annotation.color:
                    if !value.starts(with: "#") {
                        throw SchemaError.invalidValue(value: value, field: field, key: key)
                    }

                case FieldKeys.Item.Annotation.sortIndex:
                    // Sort index consists of 3 parts separated by "|":
                    // - 1. page index (5 characters)
                    // - 2. character offset (6 characters)
                    // - 3. y position from top (5 characters)
                    let parts = value.split(separator: "|")
                    if parts.count != 3 || parts[0].count != 5 || parts[1].count != 6 || parts[2].count != 5 {
                        throw SchemaError.invalidValue(value: value, field: field, key: key)
                    }

                default: break
                }
            }

        case ItemTypes.attachment:
            guard let rawLinkMode = fields[FieldKeys.Item.Attachment.linkMode] else {
                throw SchemaError.missingField(key: key, field: FieldKeys.Item.Attachment.linkMode, itemType: itemType)
            }
            if LinkMode(rawValue: rawLinkMode) == nil {
                throw SchemaError.invalidValue(value: rawLinkMode, field: FieldKeys.Item.Attachment.linkMode, key: key)
            }

        default: return
        }
    }

    private static func parsePosition(from value: String?, key: String) throws -> (pageIndex: Int, rects: [[Double]]?, paths: [[Double]]?, lineWidth: Double?) {
        guard let data = value?.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data, options: .allowFragments)) as? [String: Any],
              let pageIndex = json[FieldKeys.Item.Annotation.pageIndex] as? Int else {
            throw SchemaError.invalidValue(value: (value ?? ""), field: FieldKeys.Item.Annotation.position, key: key)
        }

        if let rawRects = json[FieldKeys.Item.Annotation.rects], let parsedRects = rawRects as? [[Double]] {
            // Rects consist of minX, minY, maxX, maxY coordinates, they can't be empty
            if parsedRects.isEmpty || parsedRects.first(where: { $0.count != 4 }) != nil {
                throw SchemaError.invalidValue(value: "\(parsedRects)", field: FieldKeys.Item.Annotation.rects, key: key)
            }
            return (pageIndex, parsedRects, nil, nil)
        }

        if let rawPaths = json[FieldKeys.Item.Annotation.paths], let parsedPaths = rawPaths as? [[Double]], let lineWidth = json[FieldKeys.Item.Annotation.lineWidth] as? Double {
            // Paths store points where x and y values follow one after each other, so the coordinates array always has to have even number of coordinates.
            if parsedPaths.isEmpty || parsedPaths.first(where: { $0.count % 2 != 0 }) != nil {
                throw SchemaError.invalidValue(value: "\(parsedPaths)", field: FieldKeys.Item.Annotation.paths, key: key)
            }
            return (pageIndex, nil, parsedPaths, lineWidth)
        }

        // If both paths and rects are missing, position of annotation is unknown and therefore invalid.
        throw SchemaError.invalidValue(value: (value ?? ""), field: FieldKeys.Item.Annotation.position, key: key)
    }

    /// Checks whether given field is a known field for given item type.
    /// - parameter field: Field to check.
    /// - parameter schema: Schema for given item type.
    /// - parameter itemType: Raw item type of item.
    /// - returns: `true` if field is a known field for given item, `false` otherwise.
    private static func isKnownField(_ field: String, in schema: [FieldSchema], itemType: String) -> Bool {
        // Note is not a field stored in schema but we consider it as one, since it can be returned with fields together with other data.
        if field == FieldKeys.Item.note || schema.contains(where: { $0.field == field }) { return true }

        switch itemType {
        case ItemTypes.annotation:
            // Annotations don't have some fields that are returned by backend in schema, so we have to filter them out here manually.
            return FieldKeys.Item.Annotation.knownKeys.contains(field)
        case ItemTypes.attachment:
            // Attachments don't have some fields that are returned by backend in schema, so we have to filter them out here manually.
            return FieldKeys.Item.Attachment.knownKeys.contains(field)
        default:
            // Field not found in schema and is not a special case.
            return false
        }
    }
}

struct TagResponse {
    enum Error: Swift.Error {
        case unknownTagType
    }

    let tag: String
    let type: RTypedTag.Kind

    init(tag: String, type: RTypedTag.Kind) {
        self.tag = tag
        self.type = type
    }

    init(response: [String: Any]) throws {
        let rawType = (try? response.apiGet(key: "type")) ?? 0

        guard let type = RTypedTag.Kind(rawValue: rawType) else {
            throw Error.unknownTagType
        }

        self.tag = try response.apiGet(key: "tag")
        self.type = type
    }

    var automaticCopy: TagResponse {
        return TagResponse(tag: self.tag, type: RTypedTag.Kind.automatic)
    }
}

struct CreatorResponse {
    let creatorType: String
    let firstName: String?
    let lastName: String?
    let name: String?

    init(response: [String: Any]) throws {
        self.creatorType = try response.apiGet(key: "creatorType")
        self.firstName = response["firstName"] as? String
        self.lastName = response["lastName"] as? String
        self.name = response["name"] as? String
    }
}

struct RelationResponse {

}

struct UserResponse {
    let id: Int
    let name: String
    let username: String

    init(response: [String: Any]) throws {
        self.id = try response.apiGet(key: "id")
        self.name = try response.apiGet(key: "name")
        self.username = try response.apiGet(key: "username")
    }
}
