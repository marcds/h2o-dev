#'
#' Transmogrify A User Defined Function Into A Cascade AST
#'
#' A function has three parts:
#'  1. A name
#'  2. Arguments
#'  3. A body
#'
#' If it has been deteremined that a function is user-defined, then it must become a Cascade AST.
#'
#' The overall strategy for collecting up a function is to avoid densely packed recursive calls, each attempting to handle
#' the various corner cases.
#'
#' Instead, the thinking is that there are a limited number of statement types in a function body:
#'  1. control flow: if, else, while, for, return
#'  2. assignments
#'  3. operations/function calls
#'  4. Implicit return statement
#'
#' Implicit return statements are the last statement in a closure. Statements that are not implicit return statements
#' are optimized away by the back end.
#'
#' Since the statement types can be explicitly defined, there is only a need for processing a statement of the 3rd kind.
#' Therefore, all recursive calls are funneled into a single statement processing function.
#'
#' From now on, statements will refer to statemets of the 3rd kind.
#'
#' Simple statements can be further grouped into the following ways (excuse abuse of `dispatch` lingo below):
#'
#'  1. Unary operations  (dispatch to .h2o.unop )
#'  2. Binary Operations (dispatch to .h2o.binop)
#'  3. Prefix Operations (dispatch to .h2o.varop)
#'  4. User Defined Function Call
#'  5. Anonymous closure
#'
#' Of course "real" statements are mixtures of these simple statements, but these statements are handled recursively.
#'
#' Case 4 spins off a new transmogrification for the encountered udf. If the udf is already defined in this **scope**, or in
#' some parent scope, then there is nothing to do.
#'
#' Case 5 spins off a new transmogrification for the encountered closure and replaced by an invocation of that closure.
#' If there's no assignment resulting from the closure, the closure is simply dropped (modification can only happen in the
#' global scope (scope used in usual sense here)).
#'
#'
#' NB:
#' **scope**: Here scopes are defined in terms of a closure.
#'            *this* scope knows about all functions and all if its parents functions.
#'            They are implemented as nested environments.
#'


#'
#' Retrieve the slot value from the object given its name and return it as a list.
.slots<-
function(name, object) {
    ret <- list(slot(object, name))
    names(ret) <- name
    ret
}

#'
#' Cast an S4 AST object to a list.
#'
#'
#' For each slot in `object`, create a list entry of name "slotName", with value given by the slot.
#'
#' To unpack this information, .ASTToList depends on a secondary helper function `.slots(...)`.
#' Finally, the result of the lapply is unlisted a single level, such that a vector of lists is returned
#' rather than a list of lists. This helps avoids anonymous lists.
.ASTToList<-
function(object) {
  return( unlist(recursive = FALSE, lapply(slotNames(object), .slots, object)))
}

#'
#' The AST visitor method.
#'
#' This method represents a map between an AST S4 object and a regular R list,
#' which is suitable for the rjson::toJSON method.
#'
#' Given a node, the `visitor` function recursively "list"-ifies the node's S4 slots and then returns the list.
#'
#' A node that has a "root" slot is an object of type ASTOp. An ASTOp will always have a "children" slot representing
#' its operands. A root node is the most general type of input, while an object of type ASTFrame or ASTNumeric is the
#' most specific. This method relies on the private helper function .ASTToList(...) to map the AST S4 object to a list.
#visitor<-
#function(node) {
#  if (.hasSlot(node, "root")) {
#    root_values <- .ASTToList(node@root)
#    children <- lapply(node@children, visitor)
#    root_values$operands <- children
#    list(astop = root_values)
#  } else if (.hasSlot(node, "statements")) {
#    f_name <- node@name
#    arguments <- node@arguments
#    children <- lapply(node@statements, visitor)
#
#    l <- list(f_name, arguments, children)
#    names(l) <- c("alias", "free_variables", "body")
#    l
#  } else if (.hasSlot(node, "symbols")) {
#    l <- .ASTToList(node)
#    l$symbols <- node@symbols
#    l
#  } else if (.hasSlot(node, "arg_value") && .hasSlot(node@arg_value, "root")) {
#    l <- .ASTToList(node)
#    l$arg_value <- visitor(node@arg_value)
#    l
#  } else if (.hasSlot(node, "arg_value") && .hasSlot(node@arg_value, "statements")) {
#    l <- .ASTToList(node)
#    l$arg_value <- visitor(node@arg_value)
#    l
#  } else if (.hasSlot(node, "arg_value") && .hasSlot(node@arg_value, "symbols")) {
#    l <- .ASTToList(node)
#    l$arg_value <- node@arg_value@symbols #visitor(node@arg_value)
#    l
#  } else {
#    .ASTToList(node)
#  }
#}


#'
#' Helper function for .isUDF
#'
#' Carefully examine an environment and determine if it's a user-defined closure.
#'
.isClosure <- function(e) {

  # if env is defined in the global environment --> it is user defined
  if (identical(e, .GlobalEnv)) return(TRUE)

  # otherwise may be a closure:

  # first check that it is not a named environment --> not part of a package
  isNamed <- environmentName(e) != ""
  if (isNamed) return(FALSE)
  # go to the parent and check again, until we hit the global, in which case return true
  .isClosure(parent.env(e))
}

#'
#' Check if the call is user defined.
#'
#' A call is user defined if its environment is the Global one, or it's a closure inside of a call existing in the Global env.
.is_udf<-
function(fun) {
  e <- tryCatch( environment(eval(fun)), error = function(x) FALSE) # get the environment of `fun`
  if (is.logical(e)) return(FALSE)                                  # if e is logical -> no environment found
  tryCatch(.isClosure(e), error = function(x) FALSE)                # environment found, but then has no parent.env
}

#'
#' Check if operator is infix.
#'
#' .INFIX_OPERATORS is defined in cosntants.R. Used by .exprToAST.
#.isInfix<-
#function(o) {
#  o %in% .INFIX_OPERATORS
#}

#'
#' Return the class of the eval-ed expression.
#'
#' A convenience method for lapply. Used by .exprToAST
#.evalClass<-
#function(i) {
#  val <- tryCatch(class(eval(i)), error = function(e) {return(NA)})
#}
#
##'
##' Check if the expr is in the formals of _any_ method in the call list.
##'
##' It doesn't matter if multiple closures have the same argument names since at execution time
##' the closure will use whatever symbol table it is closest to.
#.isFormal<-
#function(expr) {
#  formals_vec <- function(fun) { names(formals(fun)) }
#  expr %in% unlist(lapply(.pkg.env$call_list, formals_vec))
#}
#
##'
##' Helper function for .funToAST
##'
##' Recursively discover other user defined functions and hand them to .funToAST and
##' hand the *real* R expressions over to .exprToAST.
#.funToASTHelper<-
#function(piece) {
#  f_call <- piece[[1]]
#
#  # Check if user defined function
#  if (.isUDF(f_call)) {
#
#    if (is.call(piece)) {
#      return(.funToAST(piece))
#    }
#
#    # Keep a global eye on functions we have definitions for to prevent infinite recursion
#    if (! (any(f_call == .pkg.env$call_list)) || is.null(.pkg.env$call_list)) {
#      .pkg.env$call_list <- c(.pkg.env$call_list, f_call)
#      .funToAST(eval(f_call))
#    }
#  } else {
#    .exprToAST(piece)
#  }
#}
#
##'
##' Translate a function's body to an AST.
##'
##' Recursively build an AST from a UDF.
##'
##' This method is the entry point for producing an AST from a closure.
##.funToAST<-
##function(fun) {
##  if (is.call(fun)) {
##
##    res <- tryCatch(eval(fun), error = function(e) {
##      FALSE
##      }
##    )
##    # This is a fairly slimey conditional.
###    if (is.object(res)) { return(res) }
##    if ( (!is.object(res) && res == FALSE) || (is.object(res)) ) {
##      return(.exprToAST(fun[[2]]))
##    } else {
##      return(.exprToAST(eval(fun)))
##    }
##  }
##  if(is.null(body(fun)) && !(is.call(fun))) fun <- eval(fun)
##  if (.isUDF(fun)) {
##    .pkg.env$call_list <- c(.pkg.env$call_list, fun)
##    l <- as.list(body(fun))
##
##    statements <- lapply(l[-1], .funToASTHelper)
##    if (length(l[-1]) == 1) {
##
##      statements <- .funToASTHelper(eval(parse(text=deparse(eval(l[-1])))))
##    }
##    if (length(statements) == 1 && is.null(statements[[1]])) { return(NULL) }
##    .pkg.env$call_list <- NULL
##    print(fun)
##    arguments <- names(formals(fun))
##    if (is.null(formals(fun))) arguments <- "none"
##    new("ASTFun", type="UDF", name=deparse(substitute(fun)), statements=statements, arguments=arguments)
##  } else {
##    substitute(fun)
##  }
##}
#
#.funToAST<-
#function(fun) {
#  if (is.call(fun)) {
#
#    res <- tryCatch(eval(fun), error = function(e) {
#      FALSE
#      }
#    )
#    # This is a fairly slimey conditional.
##    if (is.object(res)) { return(res) }
#    if ( (!is.object(res) && res == FALSE) || (is.object(res)) ) {
#      return(.exprToAST(fun[[2]]))
#    } else {
#      return(.exprToAST(eval(fun)))
#    }
#  }
#  if(is.null(body(fun)) && !(is.call(fun))) fun <- eval(fun)
#  if (.isUDF(fun)) {
#    .pkg.env$call_list <- c(.pkg.env$call_list, fun)
#    l <- as.list(body(fun))
#
#    statements <- lapply(l[-1], .funToASTHelper)
#    if (length(l[-1]) == 1) {
#
#      statements <- .funToASTHelper(eval(parse(text=deparse(eval(l[-1])))))
#    }
#    if (length(statements) == 1 && is.null(statements[[1]])) { return(NULL) }
#    .pkg.env$call_list <- NULL
#    print(fun)
#    arguments <- names(formals(fun))
#    if (is.null(formals(fun))) arguments <- "none"
#    new("ASTFun", type="UDF", name=deparse(substitute(fun)), statements=statements, arguments=arguments)
#  } else {
#    substitute(fun)
#  }
#}




#'
#' Statement Processor
#'
#' Converts the statement into an AST.
#'
#'
#' The possible types of statements to process:
#'
#'  1. A unary operation (calls .h2o.unop)
#'      A. `!` operator
#'
#'  2. A binary operation  (calls .h2o.binop)
#'      A. ‘"+"’, ‘"-"’, ‘"*"’, ‘"^"’, ‘"%%"’, ‘"%/%"’, ‘"/"’
#'         ‘"=="’, ‘">"’, ‘"<"’, ‘"!="’, ‘"<="’, ‘">="’
#'         ‘"&"’, ‘"|"’, ‘"**"’
#'
#'  3. A prefix operation
#'      A. Unary Prefix:  ‘"abs"’,   ‘"sign"’,   ‘"sqrt"’,   ‘"ceiling"’, ‘"floor"’,
#'                        ‘"trunc"’, ‘"cummax"’, ‘"cummin"’, ‘"cumprod"’, ‘"cumsum"’,
#'                        ‘"log"’,   ‘"log10"’,  ‘"log2"’,   ‘"log1p"’,   ‘"acos"’, ‘"acosh"’,
#'                        ‘"asin"’,  ‘"asinh"’,  ‘"atan"’,   ‘"atanh"’,   ‘"exp"’,  ‘"expm1"’,
#'                        ‘"cos"’,   ‘"cosh"’,   ‘"sin"’,    ‘"sinh"’,    ‘"tan"’,  ‘"tanh"’,
#'                        ‘"gamma"’, ‘"lgamma"’, ‘"digamma"’,‘"trigamma"’, ‘"is.na"’
#'
#'      B. .h2o.varop: ‘"round"’, ‘"signif"’
#'
#'      C. .h2o.varop: ‘"max"’, ‘"min"’, ‘"range"’, ‘"prod"’, ‘"sum"’, ‘"any"’, ‘"all"’
#'
#'      D. .h2o.varop: ‘"trunc"’, ‘"log"’  (could be either unop or varop)
#'
#' Each of the above types of statements will handle their own arguments and return an appropriate AST
.process_stmnt<-
function(stmnt) {

  # convenience variable
  stmnt_list <- as.list(stmnt)

  # we got a defined op
  if (.is_op(stmnt_list[[1]])) {

    # have an operator
    op <- stmnt_list[[1]]

    # Case 2 from the comment above
    if (.is_binop(op)) {


    # Case 1, 3A above unless it's `log`
    } else if (.is_unop(op)) {

    # all varops
    } else if(.is_varop(op)) {

    # should never get here
    } else {
      stop(paste("Fail in statement processing to AST. Failing statement was: ", stmnt))
    }
  }

  # we got a user-defined function
  if (.is_udf(stmnt_list[[1]])) {

  }

  # otherwise just got a variable name to either return (if last statement, or skip if not last statement)
  if (is.name(stmnt_list[[1]]) && is.symbol(stmnt_list[[1]]) && is.language(stmnt_list[[1]])) {
    ast <- '$' %<p0-% deparse(stmnt_list[[1]])
  }
}

#'
#' Statement Parser Switchboard
#'
#' This function acts as a switchboard for the various types of statements that may exist in the body of a function.
#'
#' The possible types of statements:
#'
#'  1. Control Flow Statements:
#'      A. If
#'      B. Else
#'      C. for  -- to handle iterator-for (i in 1:5) (x in vector)
#'      D. return -- return the result
#'      E. while -- stops processing immediately. while loops are unsupported
#'
#'  2. Assignment
#'
#'  3. Function call / Operation
#'
#' This switchboard takes exactly ONE statement at a time.
.statement_to_ast_switchboard<-
function(stmnt) {

  # convenience variable
  stmnt_list <- as.list(stmnt)

  # check for `if`, `for`, `else`, `return`, `while` -- stop if `while`
  if (identical(quote(`if`),     stmnt_list[[1]])) return(.process_if_stmnt(stmnt))
  if (identical(quote(`for`),    stmnt_list[[1]])) return(.process_for_stmnt(stmnt))
  if (identical(quote(`else`),   stmnt_list[[1]])) return(.process_else_stmnt(stmnt))
  if (identical(quote(`return`), stmnt_list[[1]])) return(.process_return_stmnt(stmnt))
  if (identical(quote(`while`),  stmnt_list[[1]])) stop("*Unimplemented* `while` loops are not supported by h2o")

  # check assignment
  if(identical(quote(`<-`), stmnt_list[[1]])) return(.process_assign_stmnt(stmnt))
  if(identical(quote(`=`),  stmnt_list[[1]])) return(.process_assign_stmnt(stmnt))
  if(identical(quote(`->`), stmnt_list[[1]])) stop("Please use `<-` or `=` for assignment. Assigning to the right is not supported.")

  # everything else is a function call or operation
  .process_stmnt(stmnt)
}


#'
#' Produce a list of statements from a function body. The statements are ordered in first -> last.
.extract_statements<-
function(b) {
  # strip off the '{' if it's there
  stmnts <- as.list(b)
  if(identical(stmnts[[1]], quote(`{`))) stmnts <- stmnts[-1]
  stmnts
}


#'
#' Transmogrify A User Defined Function Into A Cascade AST
#'
#' A function has three parts:
#'  1. A name
#'  2. Arguments
#'  3. A body
#'
#' At this point, it's been determined that `fun` is a user defined function, and it must become an AST.
#' Pack the function call up into an AST.
#'
#' Two interesting cases to handle:
#'
#'  1. A closure defined in the body.
#'  2. A different UDF is called within the body.
#'
#'  1.
#'      A. Recognize closure declaration
#'      B. Parse the closure AST and store it to be shipped to H2O
#'      C. Swap out the declaration in the body of this function with an invocation of the closure.
#'
#'  2.
#'      A. Recognize the call
#'      B. If there's not an existing definition *in the current scope*, make one. TODO: handle closures more gracefully -- they aren't handled at all currently.
.funToAST<-
function(fun, name) {
  args <- formals(fun)
  b <- body(fun)
  stmnts <- .extract_statements(b)
  # every variable is a lookup

}