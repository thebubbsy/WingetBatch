Describe "ConvertTo-SpectreEscaped" {
    BeforeAll {
        # Dot-source the module to access internal functions
        . "$PSScriptRoot/../WingetBatch.psm1"
    }

    Context "Edge Cases" {
        It "Returns null when input is null" {
            $testInput = $null
            $output = ConvertTo-SpectreEscaped -Text $testInput
            $output | Should -BeNullOrEmpty
        }

        It "Returns empty string when input is empty" {
            $testInput = ""
            $output = ConvertTo-SpectreEscaped -Text $testInput
            $output | Should -Be ""
        }
    }

    Context "Normal Strings" {
        It "Returns the same string when no brackets are present" {
            $testInput = "Hello World"
            $output = ConvertTo-SpectreEscaped -Text $testInput
            $output | Should -Be "Hello World"
        }

        It "Does not affect other special characters" {
            # Use single quotes to avoid escaping issues. In single quotes, ' is escaped as ''
            $testInput = 'Hello! @#$%^&*()_+-={}|;'':",./<>?'
            $output = ConvertTo-SpectreEscaped -Text $testInput
            $output | Should -Be 'Hello! @#$%^&*()_+-={}|;'':",./<>?'
        }
    }

    Context "Bracket Escaping" {
        It "Escapes opening brackets" {
            $testInput = "["
            $output = ConvertTo-SpectreEscaped -Text $testInput
            $output | Should -Be "[["
        }

        It "Escapes closing brackets" {
            $testInput = "]"
            $output = ConvertTo-SpectreEscaped -Text $testInput
            $output | Should -Be "]]"
        }

        It "Escapes both brackets in a string" {
            $testInput = "[test]"
            $output = ConvertTo-SpectreEscaped -Text $testInput
            $output | Should -Be "[[test]]"
        }

        It "Escapes multiple brackets" {
            $testInput = "[tag1] [tag2]"
            $output = ConvertTo-SpectreEscaped -Text $testInput
            $output | Should -Be "[[tag1]] [[tag2]]"
        }

        It "Handles strings with mixed characters and brackets" {
            $testInput = "Price [99] is [too high]"
            $output = ConvertTo-SpectreEscaped -Text $testInput
            $output | Should -Be "Price [[99]] is [[too high]]"
        }

        It "Handles nested-looking brackets" {
            $testInput = "[[nested]]"
            $output = ConvertTo-SpectreEscaped -Text $testInput
            $output | Should -Be "[[[[nested]]]]"
        }
    }
}
