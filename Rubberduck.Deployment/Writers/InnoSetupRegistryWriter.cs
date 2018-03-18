﻿using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.Win32;
using Rubberduck.Deployment.Structs;

namespace Rubberduck.Deployment.Writers
{
    public class InnoSetupRegistryWriter
    {
        private readonly List<string> registryEntries = new List<string>();

        // Those set of const should correspond to the defined
        // functions in the .iss script so that they can be expanded
        // at the install time. 
        private const string InstallPathVariable = "{code:GetInstallPath}";
        private const string DllPathVariable = "{code:GetDllPath}";
        private const string Tlb32PathVariable = "{code:GetTlbPath32}";
        private const string Tlb64PathVariable = "{code:GetTlbPath64}";

        public string Write(IOrderedEnumerable<RegistryEntry> entries)
        {
            //Root: "HKCU"; Subkey: "subkey"; ValueType: string; ValueName: "value"; ValueData: "data"; Flags: deletekey uninsdeletekey
            foreach (var entry in entries)
            {
                const string flags = "uninsdeletekey";
                
                var snippet =
                    $@"Subkey: ""{Quote(entry.Key)}""; ValueType: {ConvertValueType(entry.Type)}; ValueName: ""{Quote(entry.Name)}""; ValueData: ""{Quote(ReplacePlaceholder(entry.Value, entry.Bitness))}""; Flags: {flags}";

                switch (entry.Bitness)
                {
                    case Bitness.IsAgnostic:
                        registryEntries.Add($@"Root: ""HKCU64""; {snippet}; Check: IsWin64");
                        registryEntries.Add($@"Root: ""HKCU""; {snippet}; Check: not IsWin64");
                        break;
                    case Bitness.IsPlatformDependent:
                        registryEntries.Add($@"Root: ""HKCU64""; {snippet}; Check: IsWin64");
                        registryEntries.Add($@"Root: ""HKCU32""; {snippet}; Check: IsWin64");
                        registryEntries.Add($@"Root: ""HKCU""; {snippet}; Check: not IsWin64");
                        break;
                    case Bitness.Is64Bit:
                        registryEntries.Add($@"Root: ""HKCU""; {snippet}; Check: IsWin64");
                        break;
                    case Bitness.Is32Bit:
                        registryEntries.Add($@"Root: ""HKCU""; {snippet}");
                        break;
                }
            }
            
            return string.Join(Environment.NewLine, registryEntries);
        }

        private string Quote(string value)
        {
            if (string.IsNullOrWhiteSpace(value)
                || value.StartsWith("{code:"))
            {
                return value;
            }

            return value.Replace("{", "{{");
        }

        private string ReplacePlaceholder(string value, Bitness bitness)
        {
            switch (value)
            {
                case PlaceHolders.InstallPath:
                    return InstallPathVariable;
                case PlaceHolders.DllPath:
                    return DllPathVariable;
                case PlaceHolders.TlbPath:
                    return bitness == Bitness.Is64Bit ? Tlb64PathVariable : Tlb32PathVariable;
                default:
                    return value;
            }
        }

        private string ConvertValueType(RegistryValueKind valueType)
        {
            // ReSharper disable once SwitchStatementMissingSomeCases
            switch (valueType)
            {
                case RegistryValueKind.String:
                    return "string";
                case RegistryValueKind.ExpandString:
                    return "expandsz";
                case RegistryValueKind.Binary:
                    return "binary";
                case RegistryValueKind.DWord:
                    return "dword";
                case RegistryValueKind.MultiString:
                    return "multisz";
                case RegistryValueKind.QWord:
                    return "qword";
                case RegistryValueKind.None:
                    return "none";
                default:
                    throw new ArgumentOutOfRangeException(nameof(valueType), valueType, null);
            }
        }
    }
}
