/*
 *  Calculator.swift
 *  Isle
 *
 *  Evaluates arithmetic typed into search: + − × ÷ % ^ and parentheses.
 *
 *  A small recursive-descent parser is used in place of NSExpression, which
 *  raises an uncatchable Objective-C exception on malformed input.
 */

import Foundation

enum Calculator {

    private static let allowedCharacters = Set("0123456789.+-*/%^()")
    private static let operatorCharacters = Set("+-*/%^(")

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 8
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    /** Returns the value of `input`, or `nil` when it isn't an arithmetic expression. */
    static func evaluate(_ input: String) -> Double? {
        let characters = Array(
            input.replacingOccurrences(of: "×", with: "*")
                .replacingOccurrences(of: "÷", with: "/")
                .replacingOccurrences(of: ",", with: "")
                .filter { !$0.isWhitespace }
        )

        guard characters.contains(where: \.isNumber),
              characters.contains(where: operatorCharacters.contains),
              characters.allSatisfy(allowedCharacters.contains)
        else { return nil }

        var parser = Parser(characters: characters)
        guard let value = parser.parseExpression(), parser.isAtEnd, value.isFinite else { return nil }
        return value
    }

    static func format(_ value: Double) -> String {
        formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    // MARK: - Parser

    /*
     Grammar, lowest to highest precedence:

         expression := term (("+" | "-") term)*
         term       := power (("*" | "/" | "%") power)*
         power      := unary ("^" power)?
         unary      := ("+" | "-") unary | primary
         primary    := number | "(" expression ")"
     */
    private struct Parser {

        let characters: [Character]
        var index = 0

        var isAtEnd: Bool { index == characters.count }

        private var current: Character? {
            index < characters.count ? characters[index] : nil
        }

        mutating func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while let symbol = current, symbol == "+" || symbol == "-" {
                index += 1
                guard let rhs = parseTerm() else { return nil }
                value = symbol == "+" ? value + rhs : value - rhs
            }
            return value
        }

        private mutating func parseTerm() -> Double? {
            guard var value = parsePower() else { return nil }
            while let symbol = current, symbol == "*" || symbol == "/" || symbol == "%" {
                index += 1
                guard let rhs = parsePower() else { return nil }
                switch symbol {
                case "*": value *= rhs
                case "/": value /= rhs
                default: value = value.truncatingRemainder(dividingBy: rhs)
                }
            }
            return value
        }

        private mutating func parsePower() -> Double? {
            guard let base = parseUnary() else { return nil }
            guard current == "^" else { return base }
            index += 1
            guard let exponent = parsePower() else { return nil }   /* Right-associative. */
            return pow(base, exponent)
        }

        private mutating func parseUnary() -> Double? {
            switch current {
            case "-":
                index += 1
                return parseUnary().map { -$0 }
            case "+":
                index += 1
                return parseUnary()
            default:
                return parsePrimary()
            }
        }

        private mutating func parsePrimary() -> Double? {
            if current == "(" {
                index += 1
                let value = parseExpression()
                guard current == ")" else { return nil }
                index += 1
                return value
            }

            let start = index
            while let character = current, character.isNumber || character == "." {
                index += 1
            }
            return start == index ? nil : Double(String(characters[start..<index]))
        }
    }
}
