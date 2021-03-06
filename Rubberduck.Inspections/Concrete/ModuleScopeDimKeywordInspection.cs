using System.Collections.Generic;
using System.Linq;
using Antlr4.Runtime;
using Antlr4.Runtime.Misc;
using Rubberduck.Inspections.Abstract;
using Rubberduck.Inspections.Results;
using Rubberduck.Parsing;
using Rubberduck.Parsing.Grammar;
using Rubberduck.Parsing.Inspections.Abstract;
using Rubberduck.Resources.Inspections;
using Rubberduck.Parsing.VBA;
using Rubberduck.VBEditor;

namespace Rubberduck.Inspections.Concrete
{
    public sealed class ModuleScopeDimKeywordInspection : ParseTreeInspectionBase
    {
        public ModuleScopeDimKeywordInspection(RubberduckParserState state) 
            : base(state) { }

        public override IInspectionListener Listener { get; } = new ModuleScopedDimListener();

        protected override IEnumerable<IInspectionResult> DoGetInspectionResults()
        {
            return Listener.Contexts
                .Where(result => !IsIgnoringInspectionResultFor(result.ModuleName, result.Context.Start.Line))
                .SelectMany(result => result.Context.GetDescendents<VBAParser.VariableSubStmtContext>()
                        .Select(r => new QualifiedContext<ParserRuleContext>(result.ModuleName, r)))
                .Select(result => new QualifiedContextInspectionResult(this,
                                                       string.Format(InspectionResults.ModuleScopeDimKeywordInspection, ((VBAParser.VariableSubStmtContext)result.Context).identifier().GetText()),
                                                       result));
        }

        public class ModuleScopedDimListener : VBAParserBaseListener, IInspectionListener
        {
            private readonly List<QualifiedContext<ParserRuleContext>> _contexts = new List<QualifiedContext<ParserRuleContext>>();
            public IReadOnlyList<QualifiedContext<ParserRuleContext>> Contexts => _contexts;

            public QualifiedModuleName CurrentModuleName { get; set; }

            public void ClearContexts()
            {
                _contexts.Clear();
            }

            public override void ExitVariableStmt([NotNull] VBAParser.VariableStmtContext context)
            {
                if (context.DIM() != null && context.Parent is VBAParser.ModuleDeclarationsElementContext)
                {
                    _contexts.Add(new QualifiedContext<ParserRuleContext>(CurrentModuleName, context));
                }
            }
        }
    }
}